//! 萤火虫输入法 CLI：开发/测试原型。
//!
//! 演示竖切：五笔码 → 候选 → 上屏 → 模式切换；并接入 `ime-config`：
//! 启动读 `config.toml`（`--config`/`IME_CONFIG_PATH` 指定），`mode` 决定初始模式，
//! `candidate.count` 决定每页候选数；运行中外部改配置即时生效（`subscribe` + `FileWatcher`）。
//!
//! 码表来源（T-M1-09）：优先用 `--table <路径>` / `IME_TABLE_PATH` 指定的 TSV
//! 数据文件（`code\ttext\tweight`）；未提供时回退到内置最小示例表（供 CI）。

#![forbid(unsafe_code)]

use std::io::{self, Write};
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ime_config::{Config, ConfigStore, ConfigValue, FileWatcher};
use ime_core::{InputMode, Session};
use ime_pinyin::{PinyinEngine, TablePinyinBackend};
use ime_table::{CodeTableEngine, Table};

/// 指定码表路径的环境变量名。
const ENV_TABLE_PATH: &str = "IME_TABLE_PATH";
/// 指定拼音单字表路径的环境变量名。
const ENV_PINYIN_CHARS_PATH: &str = "IME_PINYIN_CHARS_PATH";
/// 指定拼音词表路径的环境变量名。
const ENV_PINYIN_WORDS_PATH: &str = "IME_PINYIN_WORDS_PATH";
/// 指定配置路径的环境变量名。
const ENV_CONFIG_PATH: &str = "IME_CONFIG_PATH";
/// 未提供 `--config`/环境变量时的默认配置路径（仅开发 CLI；平台路径属 P1-M3）。
const DEFAULT_CONFIG_PATH: &str = "config.toml";
/// 拼音最大码长（宽松上限：最长音节 6，允许连续多音节短语）。
const MAX_PINYIN_LEN: usize = 32;

/// 内置回退表：极小示例（供无数据文件的 CI；正式数据见 `data/generated/wubi86-core.tsv`）。
fn sample_table() -> Table {
    let singles: &[(&str, &str, i32)] = &[
        ("g", "一", 100),
        ("gggg", "一", 100),
        ("gggg", "王", 90),
        ("q", "我", 100),
        ("trnt", "我", 100),
        ("wq", "你", 100),
        ("wqiy", "你", 100),
        ("vb", "好", 90),
        ("gg", "五", 80),
        ("k", "中", 100),
        ("khk", "中", 100),
        ("l", "国", 100),
        ("lgyi", "国", 100),
        ("w", "人", 100),
        ("r", "的", 100),
        ("j", "是", 100),
        ("llll", "田", 80),
        ("oooo", "火", 80),
        ("mmmm", "山", 80),
    ];
    let phrases: &[(&str, &str, i32)] = &[
        ("kwwl", "中华人民共和国", 100),
        ("ltif", "输入法", 100),
        ("khyy", "中文", 95),
        ("ggtt", "五笔", 90),
        ("gtpg", "五笔字型", 85),
    ];

    let mut table = Table::new();
    for (code, text, weight) in singles.iter().chain(phrases.iter()) {
        table.insert(code, text, *weight);
    }
    table.finalize();
    table
}

/// 内置回退拼音表：极小示例（供无数据文件的 CI；正式数据见 `data/generated/pinyin-*.tsv`）。
fn sample_pinyin() -> TablePinyinBackend {
    let chars = "# 音节\t字\tweight\n\
                 wo\t我\t100\n\
                 ni\t你\t90\n\
                 hao\t好\t80\n\
                 shi\t是\t70\n\
                 zhong\t中\t60\n\
                 wen\t文\t55\n\
                 guo\t国\t50\n\
                 ren\t人\t45\n\
                 de\t的\t40\n\
                 le\t了\t35\n";
    let words = "# 拼音\t词\tweight\n\
                 ni hao\t你好\t200\n\
                 shi jie\t世界\t180\n\
                 zhong wen\t中文\t160\n\
                 ren min\t人民\t150\n\
                 wo men\t我们\t140\n\
                 zhong guo\t中国\t130\n";
    TablePinyinBackend::from_tsv(chars, words, "内置回退拼音表").expect("样本拼音表恒可解析")
}

fn print_candidates(session: &Session, page_size: usize) {
    let candidates = session.candidates();
    if candidates.is_empty() {
        println!("  （无候选）buffer={:?}", session.buffer());
        return;
    }
    let shown: Vec<String> = candidates
        .iter()
        .take(page_size)
        .enumerate()
        .map(|(i, c)| {
            let mark = if c.is_prefix { "…" } else { "" };
            format!("{}.{}{}", i + 1, c.text, mark)
        })
        .collect();
    println!("  {}", shown.join("  "));
}

/// 解析码表路径：命令行 `--table` / `-t` > 环境变量 [`ENV_TABLE_PATH`]。
fn resolve_table_path() -> Option<PathBuf> {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].to_string_lossy();
        if arg == "--table" || arg == "-t" {
            if let Some(next) = args.get(i + 1) {
                return Some(PathBuf::from(next));
            }
        } else if let Some(path) = arg.strip_prefix("--table=") {
            return Some(PathBuf::from(path));
        }
        i += 1;
    }
    std::env::var_os(ENV_TABLE_PATH).map(PathBuf::from)
}

/// 解析拼音数据路径：命令行 `--pinyin-chars <路径>` / `--pinyin-words <路径>` > 环境变量。
fn resolve_pinyin_paths() -> (Option<PathBuf>, Option<PathBuf>) {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let mut chars = None;
    let mut words = None;
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].to_string_lossy();
        if arg == "--pinyin-chars" {
            if let Some(next) = args.get(i + 1) {
                chars = Some(PathBuf::from(next));
                i += 1;
            }
        } else if let Some(path) = arg.strip_prefix("--pinyin-chars=") {
            chars = Some(PathBuf::from(path));
        } else if arg == "--pinyin-words" {
            if let Some(next) = args.get(i + 1) {
                words = Some(PathBuf::from(next));
                i += 1;
            }
        } else if let Some(path) = arg.strip_prefix("--pinyin-words=") {
            words = Some(PathBuf::from(path));
        }
        i += 1;
    }
    let chars = chars.or_else(|| std::env::var_os(ENV_PINYIN_CHARS_PATH).map(PathBuf::from));
    let words = words.or_else(|| std::env::var_os(ENV_PINYIN_WORDS_PATH).map(PathBuf::from));
    (chars, words)
}

/// 解析配置路径：命令行 `--config <路径>` / `-c` > 环境变量 [`ENV_CONFIG_PATH`] > 默认 [`DEFAULT_CONFIG_PATH`]。
fn resolve_config_path() -> PathBuf {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    let mut i = 0;
    while i < args.len() {
        let arg = args[i].to_string_lossy();
        if arg == "--config" || arg == "-c" {
            if let Some(next) = args.get(i + 1) {
                return PathBuf::from(next);
            }
        } else if let Some(path) = arg.strip_prefix("--config=") {
            return PathBuf::from(path);
        }
        i += 1;
    }
    std::env::var_os(ENV_CONFIG_PATH)
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from(DEFAULT_CONFIG_PATH))
}

/// 加载码表：数据文件优先，失败则回退到内置示例表；返回 `(table, 来源描述)`。
fn load_table() -> (Table, String) {
    let Some(path) = resolve_table_path() else {
        return (sample_table(), "内置回退码表（未提供数据文件）".to_string());
    };
    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("错误：无法读取码表 {}：{e}", path.display());
            std::process::exit(1);
        }
    };
    match Table::from_tsv(&text) {
        Ok(table) => {
            let source = format!(
                "{}（{} 码，{} 字节）",
                path.display(),
                table.len(),
                text.len()
            );
            (table, source)
        }
        Err(e) => {
            eprintln!("错误：码表 {} 解析失败：{e}", path.display());
            std::process::exit(1);
        }
    }
}

/// 读取数据文件；失败打印错误并退出。
fn read_or_exit(path: &std::path::Path, label: &str) -> String {
    match std::fs::read_to_string(path) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("错误：无法读取{label} {}：{e}", path.display());
            std::process::exit(1);
        }
    }
}

/// 加载拼音表：两份数据文件都提供时读取；否则回退内置示例；返回 `(backend, 来源描述)`。
fn load_pinyin() -> (TablePinyinBackend, String) {
    let (chars_path, words_path) = resolve_pinyin_paths();
    match (chars_path, words_path) {
        (Some(chars), Some(words)) => {
            let chars_text = read_or_exit(&chars, "拼音字表");
            let words_text = read_or_exit(&words, "拼音词表");
            match TablePinyinBackend::from_tsv(&chars_text, &words_text, "内置轻量拼音") {
                Ok(backend) => {
                    let source = format!(
                        "{} + {}（{} 音节，{} 字，{} 词）",
                        chars.display(),
                        words.display(),
                        backend.syllable_count(),
                        backend.char_count(),
                        backend.word_count()
                    );
                    (backend, source)
                }
                Err(e) => {
                    eprintln!("错误：拼音表解析失败：{e}");
                    std::process::exit(1);
                }
            }
        }
        _ => (
            sample_pinyin(),
            "内置回退拼音表（未提供数据文件）".to_string(),
        ),
    }
}

/// 由配置快照读取 `mode` 对应的 [`InputMode`]；缺失/非法返回 `None`。
fn mode_of(config: &Config) -> Option<InputMode> {
    match config.get("mode") {
        Some(ConfigValue::String(s)) => s.as_str().parse().ok(),
        _ => None,
    }
}

/// 读取配置中的初始输入模式；缺失/非法回落默认混输。
fn config_mode(config: &Config) -> InputMode {
    mode_of(config).unwrap_or(InputMode::Mixed)
}

/// 读取每页候选数；缺失/非法回落 Schema 默认 7（范围 3–9 由 Schema 保证）。
fn candidate_count(config: &Config) -> usize {
    match config.get("candidate.count") {
        Some(ConfigValue::Int(n)) if (3..=9).contains(n) => *n as usize,
        _ => 7,
    }
}

fn main() {
    let (table, source) = load_table();
    let (pinyin_backend, pinyin_source) = load_pinyin();

    let config_path = resolve_config_path();
    let store = Arc::new(match ConfigStore::load(&config_path) {
        Ok(store) => store,
        Err(e) => {
            eprintln!("错误：配置文件 {} 加载失败：{e}", config_path.display());
            std::process::exit(1);
        }
    });

    let mut session = Session::new(config_mode(store.snapshot().as_ref()));
    session.set_wubi_engine(Box::new(CodeTableEngine::new(table, 4)));
    session.set_pinyin_engine(Box::new(PinyinEngine::new(
        Box::new(pinyin_backend),
        MAX_PINYIN_LEN,
    )));

    // 订阅配置变更：外部编辑经 FileWatcher 重载后广播；`:set` 也走同一广播。
    let pending_mode = Arc::new(Mutex::new(None::<InputMode>));
    let pending_mode_clone = Arc::clone(&pending_mode);
    store.subscribe(move |key, config| {
        println!("[config] {key} 已变更");
        if key == "mode" {
            if let Some(mode) = mode_of(config) {
                if let Ok(mut pending) = pending_mode_clone.lock() {
                    *pending = Some(mode);
                }
            }
        }
    });

    let _watcher = FileWatcher::start(
        Arc::clone(&store),
        Duration::from_millis(300),
        Duration::from_millis(150),
    );

    println!("萤火虫输入法 ime-cli（P1-M2 混输）");
    println!("  码表：{source}");
    println!("  拼音：{pinyin_source}");
    println!("  配置：{}", config_path.display());
    println!("  输入码回车上屏；:lookup <码> | :mode [mixed|wubi|pinyin] | :set <键> <值> | :help | :quit");

    let stdin = io::stdin();
    loop {
        // 应用配置变更（mode 外改后即时生效，无需重启）。
        if let Some(mode) = pending_mode
            .lock()
            .ok()
            .and_then(|mut pending| pending.take())
        {
            session.set_mode(mode);
        }
        let page_size = candidate_count(store.snapshot().as_ref());

        print!("{}> ", session.mode());
        io::stdout().flush().ok();

        let mut line = String::new();
        if stdin.read_line(&mut line).is_err() {
            break;
        }
        let line = line.trim();
        if line.is_empty() {
            continue;
        }

        match line {
            ":quit" | ":q" => break,
            ":help" => {
                println!(
                    "  命令：<码/拼音> 回车上屏 | :lookup <码> | :mode [mixed|wubi|pinyin] | :set <键> <值> | :quit"
                );
                continue;
            }
            ":mode" => {
                println!("  当前模式: {}", session.mode());
                continue;
            }
            _ => {}
        }

        if let Some(mode) = line.strip_prefix(":mode ") {
            match mode.trim().parse::<InputMode>() {
                Ok(m) => {
                    session.set_mode(m);
                    println!("  已切换到 {m}");
                }
                Err(_) => println!("  未知模式（mixed|wubi|pinyin）"),
            }
            continue;
        }

        // 调试写入命令：唯一写路径经 ime-config::set（校验 → 原子写 → 快照 → 广播）。
        if let Some(rest) = line.strip_prefix(":set ") {
            let rest = rest.trim_start();
            let (key, value) = match rest.split_once(char::is_whitespace) {
                Some((key, value)) => (key, value.trim()),
                None => {
                    println!("  用法：:set <键> <值>");
                    continue;
                }
            };
            match store.set(key, value) {
                Ok(()) => println!("  已设置 {key} = {value}"),
                Err(e) => println!("  设置失败：{e}"),
            }
            continue;
        }

        if let Some(code) = line.strip_prefix(":lookup ") {
            for ch in code.chars() {
                session.handle_key(ch);
            }
            print_candidates(&session, page_size);
            session.cancel();
            continue;
        }

        // 普通输入：逐字喂入
        for ch in line.chars() {
            session.handle_key(ch);
        }

        if session.composing() && !session.candidates().is_empty() {
            print_candidates(&session, page_size);
            session.handle_key(' ');
            println!("  上屏: {}", session.committed());
        } else if session.composing() {
            print_candidates(&session, page_size);
            session.cancel();
        } else if !session.committed().is_empty() {
            println!("  上屏: {}", session.committed());
        }
    }

    println!("再见。");
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_config_path() -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "ime-cli-config-{}-{nanos}.toml",
            std::process::id()
        ))
    }

    #[test]
    fn mode_of_and_config_mode_read_snapshot() {
        let path = temp_config_path();
        fs::write(&path, "mode = \"wubi\"\n").unwrap();
        let store = ConfigStore::load(&path).unwrap();
        let snapshot = store.snapshot();
        assert_eq!(mode_of(snapshot.as_ref()), Some(InputMode::WubiOnly));
        assert_eq!(config_mode(snapshot.as_ref()), InputMode::WubiOnly);
        let _ = fs::remove_file(&path);
    }

    #[test]
    fn candidate_count_reads_file_and_falls_back_to_default() {
        let path = temp_config_path();
        fs::write(&path, "[candidate]\ncount = 5\n").unwrap();
        let store = ConfigStore::load(&path).unwrap();
        assert_eq!(candidate_count(store.snapshot().as_ref()), 5);
        let _ = fs::remove_file(&path);

        // 文件缺失 → Schema 默认 7。
        let missing = temp_config_path();
        let store = ConfigStore::load(&missing).unwrap();
        assert_eq!(candidate_count(store.snapshot().as_ref()), 7);
        let _ = fs::remove_file(&missing);
    }
}
