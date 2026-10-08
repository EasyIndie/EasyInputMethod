//! 持久化：原子写（temp + fsync + rename）、文件锁、迁移、首次生成带注释文件。
//!
//! 铁律 R1：`config.toml` 是唯一持久真值；写入永远走本模块的原子替换。

use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime};

use toml_edit::{DocumentMut, Item, Table, Value};

use crate::config::{Config, ConfigValue};
use crate::schema::{self, ValueType};
use crate::ConfigError;

/// 锁文件陈旧阈值：超过视为 crash 残留（唯一写者 = IME 进程，此锁仅作底层防护）。
const STALE_LOCK_TIMEOUT: Duration = Duration::from_secs(30);

/// 读取文件全文；文件不存在返回 `Ok(None)`。
pub(crate) fn read_text(path: &Path) -> Result<Option<String>, ConfigError> {
    match File::open(path) {
        Ok(mut file) => {
            let mut text = String::new();
            file.read_to_string(&mut text)
                .map_err(|source| ConfigError::Io {
                    path: path.to_path_buf(),
                    source,
                })?;
            Ok(Some(text))
        }
        Err(source) if source.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(source) => Err(ConfigError::Io {
            path: path.to_path_buf(),
            source,
        }),
    }
}

/// 解析 TOML 文本，把错误转成带行号的 [`ConfigError::Parse`]。
pub(crate) fn parse_document(text: &str) -> Result<DocumentMut, ConfigError> {
    text.parse::<DocumentMut>()
        .map_err(|err: toml_edit::TomlError| {
            let (line, col) = err
                .span()
                .map(|span| line_col_at(text, span.start))
                .unwrap_or((1, 1));
            ConfigError::Parse {
                line: Some(line),
                col: Some(col),
                message: err.message().to_string(),
            }
        })
}

/// 按 Schema 生成带中文注释的首份配置文件内容。
pub(crate) fn generate_template() -> String {
    let mut out = String::new();
    out.push_str("# ═══ 萤火虫输入法 · 配置 ═══\n");
    out.push_str("# 改完保存即时生效，不用重启\n");
    out.push_str("# 以 # 开头的都是说明\n\n");

    let mut current_section: Option<&str> = None;
    let mut first = true;
    for spec in schema::SCHEMA {
        let section = section_of(spec.key);
        if section != current_section {
            if !first {
                out.push('\n');
            }
            first = false;
            if let Some(sec) = section {
                out.push('[');
                out.push_str(sec);
                out.push_str("]\n");
            }
            current_section = section;
        }
        out.push_str(leaf_of(spec.key));
        out.push_str(" = ");
        out.push_str(spec.default);
        out.push_str("  # ");
        out.push_str(spec.doc_zh);
        out.push('\n');
    }
    out
}

/// 把已校验的值写入文档（只改目标键，保留用户其它键、注释与格式）。
pub(crate) fn set_value(
    doc: &mut DocumentMut,
    key: &str,
    value: ConfigValue,
) -> Result<(), ConfigError> {
    let mut item = toml_item(value);
    preserve_value_decor(doc, key, &mut item);
    match section_of(key) {
        None => {
            doc.as_table_mut().insert(key, item);
        }
        Some(section) => {
            let table = ensure_table(doc.as_table_mut(), section)?;
            table.insert(leaf_of(key), item);
        }
    }
    Ok(())
}

/// 保留目标键原有的值级装饰（行尾中文注释、等号两侧空白），避免 `set` 破坏用户格式。
fn preserve_value_decor(doc: &DocumentMut, key: &str, new_item: &mut Item) {
    let Some(old_value) = find_item(doc, key).and_then(|item| item.as_value()) else {
        return;
    };
    let Some(new_value) = new_item.as_value_mut() else {
        return;
    };
    let decor = new_value.decor_mut();
    if let Some(prefix) = old_value.decor().prefix() {
        decor.set_prefix(prefix.clone());
    }
    if let Some(suffix) = old_value.decor().suffix() {
        decor.set_suffix(suffix.clone());
    }
}

fn find_item<'a>(doc: &'a DocumentMut, key: &str) -> Option<&'a Item> {
    match section_of(key) {
        None => doc.as_table().get(key),
        Some(section) => doc.as_table().get(section)?.as_table()?.get(leaf_of(key)),
    }
}

/// 从文档提取已知项（未知键忽略），返回合并快照与未知键列表。
pub(crate) fn extract_config(doc: &DocumentMut) -> Result<(Config, Vec<String>), ConfigError> {
    let mut config = Config::defaults();
    let mut unknown: Vec<String> = Vec::new();
    let root = doc.as_table();

    for (key, item) in root.iter() {
        if item.is_none() {
            continue;
        }
        if let Some(spec) = schema::find(key) {
            // 顶层已知键（v1 只有 mode）。
            config.insert(spec.key, scalar_value(spec, item)?);
        } else if has_section(key) {
            let table = item
                .as_table()
                .ok_or_else(|| ConfigError::invalid_value(key, "期望表"))?;
            for (leaf, leaf_item) in table.iter() {
                if leaf_item.is_none() {
                    continue;
                }
                let full = format!("{key}.{leaf}");
                match schema::find(&full) {
                    Some(spec) => config.insert(spec.key, scalar_value(spec, leaf_item)?),
                    None => unknown.push(full),
                }
            }
        } else {
            unknown.push(key.to_string());
        }
    }
    Ok((config, unknown))
}

/// 单向迁移：v1 尚无历史版本，占位返回原样（未来版本在此升级旧键）。
pub(crate) fn migrate(doc: DocumentMut) -> DocumentMut {
    doc
}

/// 原子写：同目录临时文件 → `fsync` → `rename`（POSIX 原子替换）。
///
/// 目录本身未额外 fsync（跨平台不可移植），持久性为尽力而为。
pub(crate) fn atomic_write(path: &Path, contents: &str) -> Result<(), ConfigError> {
    let dir = path
        .parent()
        .filter(|p| !p.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."));
    let file_name = path
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("config.toml");
    let tmp_path = dir.join(format!(".{file_name}.tmp.{}", std::process::id()));

    let result = (|| -> std::io::Result<()> {
        let mut file = File::create(&tmp_path)?;
        file.write_all(contents.as_bytes())?;
        file.sync_all()?;
        drop(file);
        fs::rename(&tmp_path, path)?;
        Ok(())
    })();

    result.map_err(|source| ConfigError::Io {
        path: path.to_path_buf(),
        source,
    })
}

/// 尽力而为的咨询锁：`create_new` 锁文件 + 陈旧超时（无 unsafe、无平台依赖）。
pub(crate) struct FileLock {
    path: PathBuf,
}

impl FileLock {
    pub(crate) fn acquire(config_path: &Path) -> Result<FileLock, ConfigError> {
        let lock_path = lock_path(config_path);
        loop {
            match OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(&lock_path)
            {
                Ok(mut file) => {
                    let _ = writeln!(file, "{}", std::process::id());
                    let _ = file.sync_all();
                    return Ok(FileLock { path: lock_path });
                }
                Err(source) if source.kind() == std::io::ErrorKind::AlreadyExists => {
                    if lock_is_stale(&lock_path) {
                        let _ = fs::remove_file(&lock_path);
                        continue;
                    }
                    return Err(ConfigError::Locked { path: lock_path });
                }
                Err(source) => {
                    return Err(ConfigError::Io {
                        path: lock_path,
                        source,
                    })
                }
            }
        }
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

fn lock_path(config_path: &Path) -> PathBuf {
    let mut os = config_path.as_os_str().to_owned();
    os.push(".lock");
    PathBuf::from(os)
}

fn lock_is_stale(lock_path: &Path) -> bool {
    fs::metadata(lock_path)
        .and_then(|m| m.modified())
        .ok()
        .and_then(|modified| SystemTime::now().duration_since(modified).ok())
        .map(|age| age > STALE_LOCK_TIMEOUT)
        .unwrap_or(true)
}

fn toml_item(value: ConfigValue) -> Item {
    Item::Value(match value {
        ConfigValue::Bool(b) => Value::from(b),
        ConfigValue::Int(n) => Value::from(n),
        ConfigValue::String(s) => Value::from(s),
    })
}

fn ensure_table<'a>(root: &'a mut Table, section: &str) -> Result<&'a mut Table, ConfigError> {
    if root.get(section).is_none() {
        root.insert(section, Item::Table(Table::new()));
    }
    root.get_mut(section)
        .and_then(|item| item.as_table_mut())
        .ok_or_else(|| ConfigError::invalid_value(section, "期望表"))
}

fn scalar_value(
    spec: &'static schema::OptionSpec,
    item: &Item,
) -> Result<ConfigValue, ConfigError> {
    match item.as_value() {
        Some(value) => scalar_from_value(spec, value),
        None => Err(ConfigError::invalid_value(spec.key, "期望标量值")),
    }
}

fn scalar_from_value(spec: &schema::OptionSpec, value: &Value) -> Result<ConfigValue, ConfigError> {
    match spec.value_type {
        ValueType::Bool => value
            .as_bool()
            .map(ConfigValue::Bool)
            .ok_or_else(|| ConfigError::invalid_value(spec.key, "期望 true 或 false")),
        ValueType::Int { min, max } => value
            .as_integer()
            .filter(|n| (min..=max).contains(n))
            .map(ConfigValue::Int)
            .ok_or_else(|| {
                ConfigError::invalid_value(spec.key, format!("期望 [{min}, {max}] 内的整数"))
            }),
        ValueType::Enum { values } => value
            .as_str()
            .filter(|s| values.contains(s))
            .map(|s| ConfigValue::String(s.to_string()))
            .ok_or_else(|| {
                ConfigError::invalid_value(spec.key, format!("期望 {}", values.join(" | ")))
            }),
        ValueType::String => value
            .as_str()
            .map(|s| ConfigValue::String(s.to_string()))
            .ok_or_else(|| ConfigError::invalid_value(spec.key, "期望字符串")),
    }
}

fn section_of(key: &str) -> Option<&str> {
    key.split_once('.').map(|(section, _)| section)
}

fn leaf_of(key: &str) -> &str {
    key.rsplit_once('.').map(|(_, leaf)| leaf).unwrap_or(key)
}

fn has_section(section: &str) -> bool {
    schema::SCHEMA.iter().any(|spec| {
        spec.key
            .strip_prefix(section)
            .is_some_and(|rest| rest.starts_with('.'))
    })
}

/// 计算字节偏移对应的 1 起行号与列号。
fn line_col_at(text: &str, byte_offset: usize) -> (usize, usize) {
    let bytes = text.as_bytes();
    let offset = byte_offset.min(bytes.len());
    let mut line = 1usize;
    let mut line_start = 0usize;
    for (i, b) in bytes.iter().enumerate().take(offset) {
        if *b == b'\n' {
            line += 1;
            line_start = i + 1;
        }
    }
    let col = std::str::from_utf8(&bytes[line_start..offset])
        .map(|s| s.chars().count())
        .unwrap_or(offset - line_start);
    (line, col + 1)
}
