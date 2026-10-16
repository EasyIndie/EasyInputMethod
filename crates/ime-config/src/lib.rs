//! 萤火虫输入法配置子系统。
//!
//! 铁律 R1–R4：`config.toml` 是唯一持久真值；运行时只有一份 `ArcSwap<Config>` 快照；
//! 只有 [`ConfigStore::set`] 能改（校验 → 原子写 → 发布快照 → 广播）；
//! 选项只在 [`schema`] 里定义一次。核心 crate 不联网、`#![forbid(unsafe_code)]`。
//!
//! [`schema`]: crate::schema

#![forbid(unsafe_code)]

mod config;
mod hotkey;
mod persist;
mod schema;
mod watch;

use std::fmt;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};

use arc_swap::ArcSwap;

pub use config::{Config, ConfigValue};
pub use hotkey::Hotkey;
pub use schema::{OptionSpec, Scope, ValueType, SCHEMA};
pub use watch::FileWatcher;

/// 错误状态的通知键（不会与 Schema 键冲突）；宿主据此刷新错误显示。
pub const CONFIG_ERROR_KEY: &str = "*error";

/// 配置错误。
#[derive(Debug)]
pub enum ConfigError {
    /// 文件 IO 错误。
    Io { path: PathBuf, source: io::Error },
    /// TOML 语法错误（行号/列号 1 起）。
    Parse {
        line: Option<usize>,
        col: Option<usize>,
        message: String,
    },
    /// 未知键。
    UnknownKey { key: String },
    /// 值非法（类型 / 范围 / 枚举）。
    InvalidValue { key: String, reason: String },
    /// 文件被并发写者锁定。
    Locked { path: PathBuf },
}

impl ConfigError {
    pub(crate) fn unknown_key(key: &str) -> Self {
        Self::UnknownKey {
            key: key.to_string(),
        }
    }

    pub(crate) fn invalid_value(key: &str, reason: impl Into<String>) -> Self {
        Self::InvalidValue {
            key: key.to_string(),
            reason: reason.into(),
        }
    }

    /// 语法错误所在行号（1 起）。
    pub fn line(&self) -> Option<usize> {
        match self {
            Self::Parse { line, .. } => *line,
            _ => None,
        }
    }
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Io { path, source } => {
                write!(f, "无法读写配置文件：{}（{source}）", path.display())
            }
            Self::Parse { line, col, message } => match (line, col) {
                (Some(l), Some(c)) => write!(f, "配置语法错误（第 {l} 行第 {c} 列）：{message}"),
                (Some(l), None) => write!(f, "配置语法错误（第 {l} 行）：{message}"),
                _ => write!(f, "配置语法错误：{message}"),
            },
            Self::UnknownKey { key } => write!(f, "未知配置项：{key}"),
            Self::InvalidValue { key, reason } => write!(f, "配置项 {key} 值非法：{reason}"),
            Self::Locked { path } => write!(f, "配置文件被锁定：{}", path.display()),
        }
    }
}

impl std::error::Error for ConfigError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

type Callback = Arc<dyn Fn(&str, &Config) + Send + Sync>;

/// 配置存储：唯一写入者。
///
/// 读侧零拷贝（`Arc<Config>`）；写侧只有 `set`（以及外部编辑触发的 `reload`）。
pub struct ConfigStore {
    path: PathBuf,
    snapshot: ArcSwap<Config>,
    subscribers: Mutex<Vec<(usize, Callback)>>,
    next_token: AtomicUsize,
    last_unknown_keys: Mutex<Vec<String>>,
    last_error: Mutex<Option<String>>,
}

impl ConfigStore {
    /// 从文件加载；文件不存在时用 Schema 默认值。
    pub fn load(path: impl Into<PathBuf>) -> Result<ConfigStore, ConfigError> {
        let path = path.into();
        let (config, unknown) = match persist::read_text(&path)? {
            Some(text) => {
                let doc = persist::migrate(persist::parse_document(&text)?);
                persist::extract_config(&doc)?
            }
            None => (Config::defaults(), Vec::new()),
        };
        Ok(ConfigStore {
            path,
            snapshot: ArcSwap::from_pointee(config),
            subscribers: Mutex::new(Vec::new()),
            next_token: AtomicUsize::new(0),
            last_unknown_keys: Mutex::new(unknown),
            last_error: Mutex::new(None),
        })
    }

    /// 从文件加载；失败（语法/IO 错误）时**降级为 Schema 默认值**，
    /// 并把可读错误保存在 [`last_error`](Self::last_error) 供宿主显示。
    pub fn load_or_defaults(path: impl Into<PathBuf>) -> ConfigStore {
        let path = path.into();
        match Self::load(&path) {
            Ok(store) => store,
            Err(err) => {
                let store = Self::with_defaults(path);
                store.set_last_error(Some(err.to_string()));
                store
            }
        }
    }

    /// 以 Schema 默认值构造，不读取文件。
    ///
    /// 供 FFI 等宿主在“首次加载失败（语法错误 / IO 错误）”时降级：
    /// 保留目标路径，让后续 `reload` 仍可指向真实文件。
    pub fn with_defaults(path: impl Into<PathBuf>) -> ConfigStore {
        ConfigStore {
            path: path.into(),
            snapshot: ArcSwap::from_pointee(Config::defaults()),
            subscribers: Mutex::new(Vec::new()),
            next_token: AtomicUsize::new(0),
            last_unknown_keys: Mutex::new(Vec::new()),
            last_error: Mutex::new(None),
        }
    }

    /// 最近一次加载/重载失败的人类可读原因（含行号）；文件正常时为 `None`。
    pub fn last_error(&self) -> Option<String> {
        self.last_error.lock().ok().and_then(|guard| guard.clone())
    }

    fn set_last_error(&self, message: Option<String>) {
        if let Ok(mut guard) = self.last_error.lock() {
            *guard = message;
        }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }

    /// 零拷贝取当前快照（`Arc` 引用，不拷贝数据）。
    pub fn snapshot(&self) -> Arc<Config> {
        self.snapshot.load_full()
    }

    /// 取单个值（配置量小，克隆可接受）。
    pub fn get(&self, key: &str) -> Option<ConfigValue> {
        self.snapshot.load_full().get(key).cloned()
    }

    /// 唯一写入路径：校验 → 原子写 → 发布快照 → 广播。
    ///
    /// 任何一步失败都不会改动文件或快照。
    pub fn set(&self, key: &str, value_toml: &str) -> Result<(), ConfigError> {
        let previous = self.last_error();
        let result = self.set_inner(key, value_toml);
        let current = result.as_ref().err().map(ToString::to_string);
        self.set_last_error(current.clone());
        if previous != current {
            self.notify(CONFIG_ERROR_KEY);
        }
        result
    }

    fn set_inner(&self, key: &str, value_toml: &str) -> Result<(), ConfigError> {
        let spec = schema::find(key).ok_or_else(|| ConfigError::unknown_key(key))?;
        let value = config::parse_literal(spec, value_toml)?;

        let _lock = persist::FileLock::acquire(&self.path)?;
        let doc = match persist::read_text(&self.path)? {
            Some(text) => persist::parse_document(&text)?,
            None => persist::parse_document(&persist::generate_template())?,
        };
        let mut doc = persist::migrate(doc);
        persist::set_value(&mut doc, key, value)?;
        let (next, unknown) = persist::extract_config(&doc)?;
        persist::atomic_write(&self.path, &doc.to_string())?;
        drop(_lock);

        self.set_unknown_keys(unknown);
        self.snapshot.store(Arc::new(next));
        self.notify(key);
        Ok(())
    }

    /// 强制从文件重载；语法错误时保留上一份快照并返回错误。
    ///
    /// 返回本次发生变化的键。错误状态发生变化时，额外广播
    /// [`CONFIG_ERROR_KEY`]，供宿主即时刷新「配置错误」提示。
    pub fn reload(&self) -> Result<Vec<String>, ConfigError> {
        let previous = self.last_error();
        let result = self.reload_inner();
        let current = result.as_ref().err().map(|e| e.to_string());
        self.set_last_error(current.clone());
        if previous != current {
            self.notify(CONFIG_ERROR_KEY);
        }
        result
    }

    fn reload_inner(&self) -> Result<Vec<String>, ConfigError> {
        let (next, unknown) = match persist::read_text(&self.path)? {
            Some(text) => {
                let doc = persist::migrate(persist::parse_document(&text)?);
                persist::extract_config(&doc)?
            }
            None => (Config::defaults(), Vec::new()),
        };

        let old = self.snapshot.load_full();
        let changed: Vec<String> = schema::SCHEMA
            .iter()
            .filter(|spec| old.get(spec.key) != next.get(spec.key))
            .map(|spec| spec.key.to_string())
            .collect();

        self.set_unknown_keys(unknown);
        self.snapshot.store(Arc::new(next));
        self.notify_changed(&changed);
        Ok(changed)
    }

    /// 订阅变更；返回订阅令牌。
    pub fn subscribe(&self, callback: impl Fn(&str, &Config) + Send + Sync + 'static) -> usize {
        let token = self.next_token.fetch_add(1, Ordering::Relaxed);
        if let Ok(mut subscribers) = self.subscribers.lock() {
            subscribers.push((token, Arc::new(callback)));
        }
        token
    }

    /// 取消订阅；返回是否确实移除了该令牌。
    pub fn unsubscribe(&self, token: usize) -> bool {
        if let Ok(mut subscribers) = self.subscribers.lock() {
            let before = subscribers.len();
            subscribers.retain(|(t, _)| *t != token);
            return subscribers.len() != before;
        }
        false
    }

    /// 最近一次加载 / 重载 / 写入时忽略的未知键（仅告警，不删除）。
    pub fn unknown_keys(&self) -> Vec<String> {
        self.last_unknown_keys
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default()
    }

    fn set_unknown_keys(&self, unknown: Vec<String>) {
        if let Ok(mut guard) = self.last_unknown_keys.lock() {
            *guard = unknown;
        }
    }

    fn notify(&self, key: &str) {
        let subscribers = self.subscriber_snapshot();
        let snapshot = self.snapshot.load_full();
        for callback in subscribers {
            callback(key, snapshot.as_ref());
        }
    }

    fn notify_changed(&self, keys: &[String]) {
        let subscribers = self.subscriber_snapshot();
        let snapshot = self.snapshot.load_full();
        for key in keys {
            for callback in &subscribers {
                callback(key, snapshot.as_ref());
            }
        }
    }

    fn subscriber_snapshot(&self) -> Vec<Callback> {
        self.subscribers
            .lock()
            .map(|guard| {
                guard
                    .iter()
                    .map(|(_, callback)| Arc::clone(callback))
                    .collect()
            })
            .unwrap_or_default()
    }
}

/// Schema 全表（设置界面 / 校验 / 注释生成的唯一来源）。
pub fn schema() -> &'static [OptionSpec] {
    SCHEMA
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

    struct TempFile(PathBuf);

    impl TempFile {
        fn new(tag: &str) -> Self {
            let nanos = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos();
            let path = std::env::temp_dir().join(format!(
                "ime-config-{tag}-{}-{nanos}.toml",
                std::process::id()
            ));
            Self(path)
        }

        fn path(&self) -> &Path {
            &self.0
        }
    }

    impl Drop for TempFile {
        fn drop(&mut self) {
            let _ = std::fs::remove_file(&self.0);
            let mut lock = self.0.as_os_str().to_owned();
            lock.push(".lock");
            let _ = std::fs::remove_file(PathBuf::from(lock));
        }
    }

    fn write(path: &Path, contents: &str) {
        std::fs::write(path, contents).unwrap();
    }

    fn read(path: &Path) -> String {
        std::fs::read_to_string(path).unwrap()
    }

    #[test]
    fn failed_writes_publish_reason_keep_state_and_recover_after_lock_release() {
        let tmp = TempFile::new("write-error");
        let store = ConfigStore::load(tmp.path()).unwrap();
        store.set("input.punctuation", "\"chinese\"").unwrap();
        let original = read(tmp.path());
        let snapshot = store.snapshot();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let notifications = Arc::clone(&seen);
        store.subscribe(move |key, _| notifications.lock().unwrap().push(key.to_string()));
        let lock = PathBuf::from(format!("{}.lock", tmp.path().display()));
        write(&lock, "test lock");
        for _ in 0..2 {
            assert!(matches!(
                store.set("input.punctuation", "\"english\""),
                Err(ConfigError::Locked { .. })
            ));
            assert_eq!(read(tmp.path()), original);
            assert_eq!(*store.snapshot(), *snapshot);
            assert!(store.last_error().unwrap().contains("被锁定"));
        }
        assert_eq!(seen.lock().unwrap().as_slice(), [CONFIG_ERROR_KEY]);
        std::fs::remove_file(lock).unwrap();
        store.set("input.punctuation", "\"english\"").unwrap();
        assert_eq!(
            store.get("input.punctuation").unwrap().as_str(),
            Some("english")
        );
        assert!(store.last_error().is_none());
        assert_eq!(
            seen.lock().unwrap().as_slice(),
            [CONFIG_ERROR_KEY, "input.punctuation", CONFIG_ERROR_KEY]
        );
        write(tmp.path(), "parent is a regular file");
        let blocked = ConfigStore::with_defaults(tmp.path().join("config.toml"));
        assert!(blocked.set("candidate.count", "5").is_err());
        assert!(blocked.last_error().unwrap().contains("无法读写"));
        assert_eq!(read(tmp.path()), "parent is a regular file");
    }

    #[test]
    fn shortcuts_reject_invalid_syntax_and_collisions_without_writes() {
        let tmp = TempFile::new("hotkeys");
        let store = ConfigStore::load(tmp.path()).unwrap();
        store.set("candidate.count", "5").unwrap();
        let original = read(tmp.path());
        let snapshot = store.snapshot();
        for value in [
            "banana",
            "m",
            "ctrl+ctrl+m",
            "ctrl++m",
            "ctrl+shift",
            "shift",
            "ctrl+enter",
        ] {
            assert!(
                store
                    .set("hotkey.toggle_mode", &format!("\"{value}\""))
                    .is_err(),
                "{value}"
            );
            assert_eq!(read(tmp.path()), original);
            assert_eq!(*store.snapshot(), *snapshot);
        }
        assert!(store
            .set("hotkey.toggle_mode", "\"ctrl+shift+space\"")
            .is_err());
        assert_eq!(read(tmp.path()), original);
        store.set("hotkey.toggle_width", "\"none\"").unwrap();
        store
            .set("hotkey.toggle_mode", "\"ctrl+shift+space\"")
            .unwrap();
        assert!(store
            .set("hotkey.toggle_width", "\"space+shift+ctrl\"")
            .is_err());
    }

    #[test]
    fn shortcut_defaults_reduce_accidental_toggles_without_overwriting_explicit_values() {
        let tmp = TempFile::new("hotkey-defaults");
        let store = ConfigStore::load(tmp.path()).unwrap();
        assert_eq!(
            store.get("hotkey.toggle_width").unwrap().as_str(),
            Some("ctrl+shift+space")
        );
        assert_eq!(
            store.get("hotkey.toggle_wubi_learning").unwrap().as_str(),
            Some("ctrl+shift+l")
        );
        assert!(store.set("hotkey.toggle_mode", "\"ctrl+shift+l\"").is_err());
        let old = "[hotkey]\ntoggle_width = \"shift+space\"\ntoggle_wubi_learning = \"none\"\n";
        write(tmp.path(), old);
        let explicit = ConfigStore::load(tmp.path()).unwrap();
        assert_eq!(
            explicit.get("hotkey.toggle_width").unwrap().as_str(),
            Some("shift+space")
        );
        assert_eq!(
            explicit
                .get("hotkey.toggle_wubi_learning")
                .unwrap()
                .as_str(),
            Some("none")
        );
        assert_eq!(read(tmp.path()), old);
    }

    #[test]
    fn shortcut_aliases_normalize_and_file_reload_preserves_good_snapshot() {
        let tmp = TempFile::new("hotkey-aliases");
        let store = ConfigStore::load(tmp.path()).unwrap();
        store
            .set(
                "hotkey.toggle_mode",
                "\"COMMAND + Option + CONTROL + Shift + M\"",
            )
            .unwrap();
        assert_eq!(
            store.get("hotkey.toggle_mode").unwrap().as_str(),
            Some("ctrl+alt+shift+cmd+m")
        );
        store.set("hotkey.toggle_width", "\"\"").unwrap();
        assert_eq!(
            store.get("hotkey.toggle_width").unwrap().as_str(),
            Some("none")
        );
        let snapshot = store.snapshot();
        write(
            tmp.path(),
            "[hotkey]\ntoggle_mode = \"ctrl+space\"\ntoggle_width = \"CONTROL + SPACE\"\n",
        );
        assert!(store.reload().is_err());
        assert_eq!(*store.snapshot(), *snapshot);
        assert!(store.last_error().unwrap().contains("冲突"));
        write(
            tmp.path(),
            "[hotkey]\ntoggle_mode = \"Control + Option + M\"\n",
        );
        store.reload().unwrap();
        assert_eq!(
            store.get("hotkey.toggle_mode").unwrap().as_str(),
            Some("ctrl+alt+m")
        );
        assert!(store.last_error().is_none());
        write(tmp.path(), "[hotkey]\ntoggle_mode = \"banana\"\n");
        assert!(ConfigStore::load(tmp.path()).is_err());
        assert!(ConfigStore::load_or_defaults(tmp.path())
            .last_error()
            .is_some());
    }

    #[test]
    fn missing_file_uses_defaults_and_first_set_generates_annotated_file() {
        let tmp = TempFile::new("first-gen");
        let store = ConfigStore::load(tmp.path()).unwrap();

        assert_eq!(store.get("candidate.count"), Some(ConfigValue::Int(7)));
        assert_eq!(store.get("mode"), Some(ConfigValue::String("mixed".into())));

        store.set("candidate.count", "9").unwrap();

        let text = read(tmp.path());
        assert!(text.contains("count = 9"));
        assert!(text.contains("每页候选数"));
        assert_eq!(store.get("candidate.count"), Some(ConfigValue::Int(9)));
    }

    #[test]
    fn set_writes_atomically_updates_snapshot_and_notifies_subscriber() {
        let tmp = TempFile::new("set-notify");
        let store = ConfigStore::load(tmp.path()).unwrap();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_clone = Arc::clone(&seen);
        store.subscribe(move |key, _config| {
            seen_clone.lock().unwrap().push(key.to_string());
        });

        store.set("candidate.count", "9").unwrap();

        assert!(read(tmp.path()).contains("count = 9"));
        assert_eq!(store.get("candidate.count"), Some(ConfigValue::Int(9)));
        let keys = seen.lock().unwrap();
        assert_eq!(keys.as_slice(), ["candidate.count"]);
    }

    #[test]
    fn deleted_line_falls_back_to_schema_default() {
        let tmp = TempFile::new("deleted-line");
        write(tmp.path(), "mode = \"wubi\"\n\n[candidate]\ncount = 5\n");
        let store = ConfigStore::load(tmp.path()).unwrap();
        assert_eq!(store.get("candidate.count"), Some(ConfigValue::Int(5)));

        write(tmp.path(), "mode = \"wubi\"\n");
        let changed = store.reload().unwrap();

        assert_eq!(store.get("candidate.count"), Some(ConfigValue::Int(7)));
        assert!(changed.iter().any(|k| k == "candidate.count"));
    }

    #[test]
    fn syntax_error_keeps_last_snapshot_and_reports_line() {
        let tmp = TempFile::new("syntax");
        write(tmp.path(), "mode = \"wubi\"\n");
        let store = ConfigStore::load(tmp.path()).unwrap();
        assert_eq!(store.get("mode"), Some(ConfigValue::String("wubi".into())));

        write(tmp.path(), "mode = \"wubi\"\ncount = [unclosed\n");
        let err = store.reload().unwrap_err();

        assert!(err.line().is_some());
        // 保留上一份可用快照。
        assert_eq!(store.get("mode"), Some(ConfigValue::String("wubi".into())));
    }

    #[test]
    fn load_or_defaults_records_error_and_reload_clears_it() {
        let tmp = TempFile::new("bad-load");
        write(tmp.path(), "mode = [oops\n");
        let store = ConfigStore::load_or_defaults(tmp.path());

        // 坏文件降级为默认值，但错误可读。
        assert_eq!(store.get("mode"), Some(ConfigValue::String("mixed".into())));
        let message = store.last_error().expect("应记录初始错误");
        assert!(message.contains("配置语法错误"));

        // 修好后 reload 清除错误。
        write(tmp.path(), "mode = \"wubi\"\n");
        assert!(store.reload().is_ok());
        assert!(store.last_error().is_none());
        assert_eq!(store.get("mode"), Some(ConfigValue::String("wubi".into())));
    }

    #[test]
    fn reload_error_notifies_error_key_and_keeps_snapshot() {
        let tmp = TempFile::new("bad-reload");
        write(tmp.path(), "mode = \"wubi\"\n");
        let store = ConfigStore::load(tmp.path()).unwrap();
        let seen = Arc::new(Mutex::new(Vec::new()));
        let seen_clone = Arc::clone(&seen);
        store.subscribe(move |key, _config| {
            seen_clone.lock().unwrap().push(key.to_string());
        });

        write(tmp.path(), "mode = [oops\n");
        assert!(store.reload().is_err());
        assert!(store.last_error().is_some());
        // 保留上一份可用快照。
        assert_eq!(store.get("mode"), Some(ConfigValue::String("wubi".into())));
        assert!(
            seen.lock().unwrap().iter().any(|k| k == CONFIG_ERROR_KEY),
            "错误状态变化应广播 CONFIG_ERROR_KEY"
        );

        // 错误状态未变时不重复广播。
        let before = seen.lock().unwrap().len();
        assert!(store.reload().is_err());
        assert_eq!(seen.lock().unwrap().len(), before);

        // 修好后错误清除并再次广播。
        write(tmp.path(), "mode = \"pinyin\"\n");
        assert!(store.reload().is_ok());
        assert!(store.last_error().is_none());
        assert_eq!(
            store.get("mode"),
            Some(ConfigValue::String("pinyin".into()))
        );
    }

    #[test]
    fn unknown_keys_are_ignored_and_preserved() {
        let tmp = TempFile::new("unknown");
        write(
            tmp.path(),
            "mode = \"pinyin\"\nfuture_option = \"keep me\"\n",
        );
        let store = ConfigStore::load(tmp.path()).unwrap();

        assert_eq!(store.unknown_keys(), ["future_option"]);
        assert_eq!(
            store.get("mode"),
            Some(ConfigValue::String("pinyin".into()))
        );

        store.set("wubi.auto_commit", "false").unwrap();

        let text = read(tmp.path());
        assert!(text.contains("future_option = \"keep me\""));
        assert!(text.contains("auto_commit = false"));
    }

    #[test]
    fn invalid_value_returns_error_and_leaves_file_unchanged() {
        let tmp = TempFile::new("invalid");
        write(tmp.path(), "mode = \"wubi\"\n");
        let store = ConfigStore::load(tmp.path()).unwrap();
        let before = read(tmp.path());

        assert!(store.set("candidate.count", "10").is_err());
        assert!(store.set("candidate.count", "abc").is_err());
        assert!(store.set("mode", "bogus").is_err());
        assert!(store.set("no.such.key", "1").is_err());

        assert_eq!(read(tmp.path()), before);
    }

    #[cfg(unix)]
    #[test]
    fn written_config_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let tmp = TempFile::new("mode");
        let store = ConfigStore::load(tmp.path()).unwrap();
        store.set("candidate.count", "5").unwrap();
        let mode = std::fs::metadata(tmp.path()).unwrap().permissions().mode() & 0o777;
        assert_eq!(mode, 0o600, "配置应为仅属主可读写（SEC-02）");
    }

    #[test]
    fn enum_and_bool_literals_accept_quoted_and_bare_forms() {
        let tmp = TempFile::new("literals");
        let store = ConfigStore::load(tmp.path()).unwrap();

        store.set("mode", "\"wubi\"").unwrap();
        assert_eq!(store.get("mode"), Some(ConfigValue::String("wubi".into())));

        store.set("wubi.auto_commit", "false").unwrap();
        assert_eq!(
            store.get("wubi.auto_commit"),
            Some(ConfigValue::Bool(false))
        );

        store.set("hotkey.toggle_mode", "ctrl+space").unwrap();
        assert_eq!(
            store.get("hotkey.toggle_mode"),
            Some(ConfigValue::String("ctrl+space".into()))
        );
    }

    #[test]
    fn watcher_reloads_on_external_edit() {
        let tmp = TempFile::new("watch");
        write(tmp.path(), "[candidate]\ncount = 5\n");
        let store = Arc::new(ConfigStore::load(tmp.path()).unwrap());

        let _watcher = FileWatcher::start(
            Arc::clone(&store),
            Duration::from_millis(10),
            Duration::from_millis(20),
        );

        std::thread::sleep(Duration::from_millis(40));
        write(tmp.path(), "[candidate]\ncount = 8\n");

        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            if store.get("candidate.count") == Some(ConfigValue::Int(8)) {
                break;
            }
            assert!(Instant::now() < deadline, "watcher 未在时限内重载");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    #[test]
    fn schema_is_single_source_and_matches_v1() {
        assert_eq!(schema().len(), 17);
        let keys: Vec<&str> = schema().iter().map(|s| s.key).collect();
        assert_eq!(
            keys,
            [
                "mode",
                "wubi.auto_commit",
                "wubi.z_key",
                "pinyin.fuzzy",
                "candidate.count",
                "candidate.page_with_comma",
                "candidate.show_wubi_learning",
                "appearance.theme",
                "hotkey.toggle_wubi_learning",
                "hotkey.toggle_mode",
                "hotkey.toggle_english",
                "hotkey.toggle_width",
                "hotkey.toggle_punctuation",
                "hotkey.toggle_variant",
                "input.punctuation",
                "input.full_width",
                "input.chinese_variant",
            ]
        );
    }
}
