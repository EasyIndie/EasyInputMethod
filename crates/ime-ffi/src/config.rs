//! 配置 ABI（`docs/配置架构.md` §9）。
//!
//! 进程级单例 [`ConfigStore`]，线程安全（内部 `ArcSwap`）。配置路径：环境变量
//! `IME_CONFIG_PATH`，未设置时回落 `config.toml`（平台真实路径属 P1-M3 宿主）。
//!
//! 契约：
//! - [`ime_config_snapshot`] 返回**借用**指针，调用方不得释放；任何 `set`/`reload`
//!   之后应重新获取。借用**按线程各自保留**，在该线程下次调用前有效；
//! - [`ime_config_get`] 返回的字符串在下次 `get`/`set`/`reload` 前有效（线程本地缓冲）；
//! - `subscribe` 回调在触发 `set`/`reload` 的线程同步派发，调用方需自行同步。

use std::cell::RefCell;
use std::ffi::{c_char, c_void, CString};
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::path::PathBuf;
use std::ptr;
use std::sync::{Arc, OnceLock};

use ime_config::{Config, ConfigError, ConfigStore, FileWatcher, Scope, ValueType};

use crate::error::{
    catch_status, catch_value, cstr_arg, IME_ERR_INVALID_INPUT, IME_ERR_IO, IME_ERR_LOCKED,
    IME_ERR_NULL, IME_ERR_PARSE, IME_ERR_UNKNOWN_KEY, IME_OK,
};

/// 指定配置路径的环境变量名。
const ENV_CONFIG_PATH: &str = "IME_CONFIG_PATH";
/// 未设置环境变量时的默认配置路径（仅 FFI；平台路径属 P1-M3 宿主）。
const DEFAULT_CONFIG_PATH: &str = "config.toml";

/// 进程级配置存储（唯一实例）。
static STORE: OnceLock<Arc<ConfigStore>> = OnceLock::new();
static WATCHER: OnceLock<FileWatcher> = OnceLock::new();
/// 宿主提供的配置路径（`ime_config_init`；优先于环境变量与默认值）。
static PATH_OVERRIDE: OnceLock<PathBuf> = OnceLock::new();
/// 配置 Schema 的 C 布局（一次性构建，指针稳定）。
static SCHEMA_LAYOUT: OnceLock<SchemaLayout> = OnceLock::new();

/// 不透明配置快照（借用，勿释放）。
#[repr(C)]
pub struct ImeConfig {
    _private: [u8; 0],
}

/// Schema 中单个选项的 C 布局。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeConfigSchemaOption {
    /// 点分键名（UTF-8，NUL 结尾）。
    pub key: *const c_char,
    /// 0=bool、1=int、2=enum、3=string。
    pub value_type: i32,
    /// 默认值 TOML 字面量（UTF-8）。
    pub default_toml: *const c_char,
    /// 中文说明（UTF-8）。
    pub doc_zh: *const c_char,
    /// 0=engine、1=candidate_window、2=appearance、3=hotkey。
    pub scope: i32,
    /// int 类型的闭区间下界（其它类型为 0）。
    pub int_min: i32,
    /// int 类型的闭区间上界（其它类型为 0）。
    pub int_max: i32,
    /// enum 取值：NUL 分隔的 UTF-8 列表，以空串结束（其它类型为单个 NUL）。
    pub enum_values: *const c_char,
    /// 设置界面用的短标题（UTF-8）。
    pub title_zh: *const c_char,
    /// enum 显示名：NUL 分隔的 UTF-8 列表，与 `enum_values` 一一对应（其它类型为单个 NUL）。
    pub enum_labels_zh: *const c_char,
}

/// Schema 的 C 布局（借用）。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeConfigSchema {
    pub items: *const ImeConfigSchemaOption,
    pub len: u32,
}

// SAFETY：这些结构体在 `SCHEMA_LAYOUT` 内一次性构建后不再变更；其中的裸指针指向
// 由同一 `SchemaLayout` 持有的 `CString`/`Vec<u8>` 缓冲，生命周期与静态变量一致，
// 故可安全地跨线程共享只读数据。
unsafe impl Send for ImeConfigSchemaOption {}
unsafe impl Sync for ImeConfigSchemaOption {}
unsafe impl Send for ImeConfigSchema {}
unsafe impl Sync for ImeConfigSchema {}

/// 变更回调：`(key, user)`；在触发 `set`/`reload` 的线程同步派发。
pub type ImeConfigChangedFn = Option<unsafe extern "C" fn(*const c_char, *mut c_void)>;

struct SchemaLayout {
    view: ImeConfigSchema,
    _options: Vec<ImeConfigSchemaOption>,
    _strings: Vec<CString>,
    _bytes: Vec<Vec<u8>>,
}

thread_local! {
    /// `ime_config_get` 的线程本地缓冲（下次调用前有效）。
    static GET_BUF: RefCell<Option<CString>> = const { RefCell::new(None) };
    /// `ime_config_last_error` 的线程本地缓冲（下次调用前有效）。
    static ERROR_BUF: RefCell<Option<CString>> = const { RefCell::new(None) };
    /// `ime_config_snapshot` 的借用：**按线程各自持有**，指针在该线程下次调用前有效。
    /// （原实现为全局单槽，并发调用会互相覆盖导致悬垂；见 T-MVP-01。）
    static SNAPSHOT_BUF: RefCell<Option<Arc<Config>>> = const { RefCell::new(None) };
}

fn config_path() -> PathBuf {
    PATH_OVERRIDE
        .get()
        .cloned()
        .or_else(|| std::env::var_os(ENV_CONFIG_PATH).map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from(DEFAULT_CONFIG_PATH))
}

/// 设定配置文件的平台路径（应由宿主在**任何其他配置调用之前**调用）。
///
/// 幂等：重复设置不覆盖首个值；存储已初始化后调用无效。返回错误码。
#[no_mangle]
pub extern "C" fn ime_config_init(path: *const c_char) -> i32 {
    catch_status(|| {
        // SAFETY：契约见 `cstr_arg`。
        let path = unsafe { cstr_arg(path)? };
        let _ = PATH_OVERRIDE.set(PathBuf::from(path));
        Ok(IME_OK)
    })
}

/// 取（或初始化）进程级配置存储。首次加载失败（语法/IO）时降级为内存默认值，
/// 保留目标路径，后续 `reload` 仍可指向真实文件。
fn store() -> &'static ConfigStore {
    let store = STORE.get_or_init(|| Arc::new(ConfigStore::load_or_defaults(config_path())));
    WATCHER.get_or_init(|| {
        FileWatcher::start(
            Arc::clone(store),
            std::time::Duration::from_millis(200),
            std::time::Duration::from_millis(150),
        )
    });
    store
}

pub(crate) fn user_dictionary_path() -> PathBuf {
    store()
        .path()
        .parent()
        .unwrap_or(std::path::Path::new("."))
        .join("user-dictionary.tsv")
}

pub(crate) fn snapshot() -> Arc<Config> {
    store().snapshot()
}

fn config_err_to_code(e: ConfigError) -> i32 {
    match e {
        ConfigError::Io { .. } => IME_ERR_IO,
        ConfigError::Parse { .. } => IME_ERR_PARSE,
        ConfigError::UnknownKey { .. } => IME_ERR_UNKNOWN_KEY,
        ConfigError::InvalidValue { .. } => IME_ERR_INVALID_INPUT,
        ConfigError::Locked { .. } => IME_ERR_LOCKED,
    }
}

/// 核心取值逻辑（与全局单例解耦，便于单测）。
fn get_impl(store: &ConfigStore, key: &str) -> Result<CString, i32> {
    let value = store.get(key).ok_or(IME_ERR_UNKNOWN_KEY)?;
    CString::new(value.to_string()).map_err(|_| IME_ERR_INVALID_INPUT)
}

/// 核心写值逻辑。
fn set_impl(store: &ConfigStore, key: &str, value_toml: &str) -> Result<(), i32> {
    store.set(key, value_toml).map_err(config_err_to_code)
}

/// 核心重载逻辑。
fn reload_impl(store: &ConfigStore) -> Result<(), i32> {
    store.reload().map(|_| ()).map_err(config_err_to_code)
}

/// 取当前快照的借用指针（勿释放；任何 `set`/`reload` 后重取）。
#[no_mangle]
pub extern "C" fn ime_config_snapshot() -> *const ImeConfig {
    catch_value(
        || {
            let arc = store().snapshot();
            let ptr = Arc::as_ptr(&arc) as *const ImeConfig;
            // 借用按线程各自保留：并发调用互不干扰，避免全局单槽被覆盖而悬垂（T-MVP-01）。
            SNAPSHOT_BUF.with(|buf| *buf.borrow_mut() = Some(arc));
            Ok(ptr)
        },
        ptr::null(),
    )
}

/// 取单个配置值（字符串形式）；未知键或错误返回 `NULL`。
#[no_mangle]
pub extern "C" fn ime_config_get(key: *const c_char) -> *const c_char {
    match catch_unwind(AssertUnwindSafe(|| {
        // SAFETY：契约见 `cstr_arg`。
        let key = unsafe { cstr_arg(key)? };
        get_impl(store(), key)
    })) {
        Ok(Ok(c)) => GET_BUF.with(|buf| {
            let ptr = c.as_ptr();
            *buf.borrow_mut() = Some(c);
            ptr
        }),
        Ok(Err(_)) | Err(_) => ptr::null(),
    }
}

/// Canonical shortcut representation; invalid or unknown input is disabled.
#[repr(C)]
#[derive(Clone, Copy, Default)]
pub struct ImeHotkey {
    pub kind: u32,
    pub modifiers: u32,
    pub key: u32,
}

#[no_mangle]
pub extern "C" fn ime_config_hotkey(key: *const c_char) -> ImeHotkey {
    catch_value(
        || {
            // SAFETY: caller supplies a readable NUL-terminated key, as for get.
            let key = unsafe { cstr_arg(key)? };
            let value = store().get(key).ok_or(IME_ERR_UNKNOWN_KEY)?;
            let value = value.as_str().ok_or(IME_ERR_INVALID_INPUT)?;
            let binding =
                ime_config::Hotkey::parse(key, value).map_err(|_| IME_ERR_INVALID_INPUT)?;
            Ok(ImeHotkey {
                kind: binding.kind,
                modifiers: binding.modifiers,
                key: binding.key,
            })
        },
        ImeHotkey::default(),
    )
}

/// 最近一次配置加载/重载失败原因（UTF-8，仍含行号）；无错误返回空串。
/// 借用指针，下次调用前有效；绝不返回 NULL。
#[no_mangle]
pub extern "C" fn ime_config_last_error() -> *const c_char {
    let message = match catch_unwind(AssertUnwindSafe(|| store().last_error())) {
        Ok(Some(message)) => message,
        _ => String::new(),
    };
    ERROR_BUF.with(|buf| {
        let c = CString::new(message).unwrap_or_default();
        let ptr = c.as_ptr();
        *buf.borrow_mut() = Some(c);
        ptr
    })
}

/// 取配置 Schema（供设置界面动态渲染，界面零硬编码）。
#[no_mangle]
pub extern "C" fn ime_config_schema() -> *const ImeConfigSchema {
    catch_value(
        || {
            let layout = SCHEMA_LAYOUT.get_or_init(build_schema);
            Ok(&layout.view as *const ImeConfigSchema)
        },
        ptr::null(),
    )
}

/// 唯一写入路径：校验 → 原子写 → 快照 → 广播。
#[no_mangle]
pub extern "C" fn ime_config_set(key: *const c_char, value_toml: *const c_char) -> i32 {
    catch_status(|| {
        // SAFETY：契约见 `cstr_arg`。
        let key = unsafe { cstr_arg(key)? };
        let value = unsafe { cstr_arg(value_toml)? };
        set_impl(store(), key, value)?;
        Ok(IME_OK)
    })
}

/// 强制从文件重载。
#[no_mangle]
pub extern "C" fn ime_config_reload() -> i32 {
    catch_status(|| {
        reload_impl(store())?;
        Ok(IME_OK)
    })
}

/// 订阅配置变更，返回订阅令牌（`<0` 表示失败）。
#[no_mangle]
pub extern "C" fn ime_config_subscribe(cb: ImeConfigChangedFn, user: *mut c_void) -> i32 {
    catch_status(|| {
        let cb = cb.ok_or(IME_ERR_NULL)?;
        // 把原始指针存为地址，绕开 raw pointer 的 `Send/Sync` 限制；
        // 回调时还原。契约：`user` 在订阅期间保持有效。
        let user_addr = user as usize;
        let token = store().subscribe(move |key, _config| {
            let c = match CString::new(key) {
                Ok(c) => c,
                Err(_) => return,
            };
            // SAFETY：`cb` 是调用方提供的合法函数指针，`user` 生命周期由调用方保证。
            unsafe { cb(c.as_ptr(), user_addr as *mut c_void) };
        });
        Ok(token as i32)
    })
}

/// 取消订阅；返回是否确实移除了该令牌。
#[no_mangle]
pub extern "C" fn ime_config_unsubscribe(token: i32) -> i32 {
    catch_status(|| {
        if token < 0 {
            return Err(IME_ERR_INVALID_INPUT);
        }
        store().unsubscribe(token as usize);
        Ok(IME_OK)
    })
}

/// 由 [`ime_config::schema`] 构建 C 布局（一次性）。
fn build_schema() -> SchemaLayout {
    let specs = ime_config::schema();
    let mut options = Vec::with_capacity(specs.len());
    let mut strings: Vec<CString> = Vec::with_capacity(specs.len() * 3);
    let mut bytes: Vec<Vec<u8>> = Vec::new();

    for spec in specs {
        let key = cstring(spec.key);
        let default_toml = cstring(spec.default);
        let doc_zh = cstring(spec.doc_zh);
        let title_zh = cstring(spec.title_zh);

        let (value_type, int_min, int_max, enum_values) = match spec.value_type {
            ValueType::Bool => (0, 0, 0, vec![0]),
            ValueType::Int { min, max } => (1, min as i32, max as i32, vec![0]),
            ValueType::Enum { values } => {
                let mut buf: Vec<u8> = Vec::new();
                for v in values {
                    buf.extend_from_slice(v.as_bytes());
                    buf.push(0);
                }
                // 末尾再补一个 NUL，形成“空串终止”（双 NUL），与 ABI 约定一致。
                buf.push(0);
                (2, 0, 0, buf)
            }
            ValueType::String => (3, 0, 0, vec![0]),
        };
        // enum 显示名（与 enum_values 一一对应）；非枚举为空列表（单个 NUL）。
        let mut enum_labels: Vec<u8> = Vec::new();
        for label in spec.enum_labels_zh {
            enum_labels.extend_from_slice(label.as_bytes());
            enum_labels.push(0);
        }
        // 始终以空串终止（双 NUL），与 enum_values 解析约定一致。
        enum_labels.push(0);
        let scope = match spec.scope {
            Scope::Engine => 0,
            Scope::CandidateWindow => 1,
            Scope::Appearance => 2,
            Scope::Hotkey => 3,
        };

        let enum_ptr = enum_values.as_ptr() as *const c_char;
        let enum_labels_ptr = enum_labels.as_ptr() as *const c_char;
        options.push(ImeConfigSchemaOption {
            key: key.as_ptr(),
            value_type,
            default_toml: default_toml.as_ptr(),
            doc_zh: doc_zh.as_ptr(),
            scope,
            int_min,
            int_max,
            enum_values: enum_ptr,
            title_zh: title_zh.as_ptr(),
            enum_labels_zh: enum_labels_ptr,
        });
        strings.push(key);
        strings.push(default_toml);
        strings.push(doc_zh);
        strings.push(title_zh);
        bytes.push(enum_values);
        bytes.push(enum_labels);
    }

    let items = options.as_ptr();
    let len = options.len() as u32;
    SchemaLayout {
        view: ImeConfigSchema { items, len },
        _options: options,
        _strings: strings,
        _bytes: bytes,
    }
}

/// `&str` → `CString`（键/默认/说明均来自 Schema，恒无 NUL，失败即 panic 代表 bug）。
fn cstring(s: &str) -> CString {
    CString::new(s).expect("Schema 字符串不应含 NUL")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::time::{SystemTime, UNIX_EPOCH};

    fn temp_path(tag: &str) -> PathBuf {
        let nanos = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "ime-ffi-config-{tag}-{}-{nanos}.toml",
            std::process::id()
        ))
    }

    #[test]
    fn get_returns_value_as_string() {
        let path = temp_path("get");
        let store = ConfigStore::load(&path).unwrap();
        let c = get_impl(&store, "mode").unwrap();
        assert_eq!(c.to_str().unwrap(), "mixed");
        let c = get_impl(&store, "candidate.count").unwrap();
        assert_eq!(c.to_str().unwrap(), "7");
        assert_eq!(
            get_impl(&store, "no.such.key").unwrap_err(),
            IME_ERR_UNKNOWN_KEY
        );
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn set_and_reload_roundtrip() {
        let path = temp_path("set");
        let store = ConfigStore::load(&path).unwrap();
        set_impl(&store, "candidate.count", "5").unwrap();
        assert_eq!(
            get_impl(&store, "candidate.count")
                .unwrap()
                .to_str()
                .unwrap(),
            "5"
        );
        assert_eq!(
            set_impl(&store, "candidate.count", "99").unwrap_err(),
            IME_ERR_INVALID_INPUT
        );
        assert_eq!(
            set_impl(&store, "no.such.key", "1").unwrap_err(),
            IME_ERR_UNKNOWN_KEY
        );
        reload_impl(&store).unwrap();
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn schema_layout_matches_v1() {
        let layout = build_schema();
        assert_eq!(layout.view.len, 15);
        let first = layout._options[0];
        // SAFETY：指针由 build_schema 的 CString/Vec 持有，测试期间有效。
        unsafe {
            assert_eq!(CStr::from_ptr(first.key).to_str().unwrap(), "mode");
            assert_eq!(CStr::from_ptr(first.title_zh).to_str().unwrap(), "输入模式");
        }
        assert_eq!(first.value_type, 2);
        // SAFETY：同上。
        let values = unsafe { cstr_list(first.enum_values) };
        assert_eq!(values, vec!["mixed", "wubi", "pinyin"]);
        // SAFETY：显示名与取值一一对应（设置界面依赖）。
        let labels = unsafe { cstr_list(first.enum_labels_zh) };
        assert_eq!(labels.len(), values.len());
        assert_eq!(labels[0], "五笔优先 + 拼音兜底");
        // 每个枚举选项的取值/显示名非空且一一对应。
        for option in &layout._options {
            if option.value_type != 2 {
                continue;
            }
            // SAFETY：枚举缓冲区与 layout 同生命周期。
            let (values, labels) = unsafe {
                (
                    cstr_list(option.enum_values),
                    cstr_list(option.enum_labels_zh),
                )
            };
            let key = unsafe { CStr::from_ptr(option.key).to_str().unwrap() };
            assert!(!values.is_empty(), "{key} 缺枚举取值");
            assert_eq!(values.len(), labels.len());
        }
    }

    #[test]
    fn subscribe_and_unsubscribe() {
        let path = temp_path("subscribe");
        let store = ConfigStore::load(&path).unwrap();
        let hits = Arc::new(AtomicUsize::new(0));
        let hits2 = Arc::clone(&hits);
        let token = store.subscribe(move |key, _| {
            assert_eq!(key, "mode");
            hits2.fetch_add(1, Ordering::SeqCst);
        });
        set_impl(&store, "mode", "wubi").unwrap();
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        assert!(store.unsubscribe(token));
        set_impl(&store, "mode", "pinyin").unwrap();
        assert_eq!(hits.load(Ordering::SeqCst), 1);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn concurrent_snapshots_do_not_share_a_single_slot() {
        // T-MVP-01：并发取快照按线程各自保留，不再互相覆盖。
        let handles: Vec<_> = (0..4)
            .map(|_| {
                std::thread::spawn(|| {
                    for _ in 0..500 {
                        assert!(!ime_config_snapshot().is_null());
                    }
                })
            })
            .collect();
        for handle in handles {
            handle.join().unwrap();
        }
    }

    #[test]
    fn last_error_is_empty_without_config_error() {
        let ptr = ime_config_last_error();
        assert!(!ptr.is_null());
        // SAFETY：指针借用自线程本地缓冲，下次调用前有效。
        assert_eq!(unsafe { CStr::from_ptr(ptr) }.to_str().unwrap(), "");
    }

    /// 测试辅助：解析 NUL 分隔的字符串列表（复制为 `String`）。
    unsafe fn cstr_list(ptr: *const c_char) -> Vec<String> {
        if ptr.is_null() {
            return Vec::new();
        }
        let mut out = Vec::new();
        let mut cur = ptr;
        loop {
            // SAFETY：列表由 build_schema 构造，以空串（单个 NUL）结束。
            let s = unsafe { CStr::from_ptr(cur) }.to_str().unwrap();
            if s.is_empty() {
                break;
            }
            out.push(s.to_string());
            // SAFETY：`s` 后紧跟一个 NUL，跳过它即下一项。
            cur = unsafe { cur.add(s.len() + 1) };
        }
        out
    }
}
