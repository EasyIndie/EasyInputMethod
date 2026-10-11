//! 常驻内存基线探针（T-P2-04 / MEM-1）。
//!
//! 按参数加载数据表并保持，然后退出；峰值 RSS 由外部 `/usr/bin/time -l` 读取，
//! 用来给「每张表的增量成本」建立可复现的基线。
//!
//! 用法（空串表示该项不加载）：
//!   cargo build --release -p ime-ffi --example mem_probe
//!   /usr/bin/time -l target/release/examples/mem_probe -- <wubi> [chars] [words] [variant]
//!
//! 例：
//!   /usr/bin/time -l target/release/examples/mem_probe -- \
//!     data/generated/wubi86-core.tsv data/generated/pinyin-chars.tsv \
//!     data/generated/pinyin-core.tsv data/generated/variant-s2t.tsv

use std::ffi::CString;
use std::os::raw::{c_char, c_void};

// 引用一下 crate，确保链接 `ime-ffi`（下方 C ABI 符号在其 rlib 中）。
const _: u32 = ime_ffi::IME_ABI_VERSION;

// 直接声明 C ABI 符号（crate 未把这些 FFI 函数重导出为 Rust API）。
extern "C" {
    fn ime_session_new_with_data(
        wubi_path: *const c_char,
        pinyin_chars_path: *const c_char,
        pinyin_words_path: *const c_char,
    ) -> *mut c_void;
    fn ime_session_set_variant_data(session: *mut c_void, path: *const c_char) -> i32;
    fn ime_session_free(session: *mut c_void);
}

fn c(path: &str) -> *const c_char {
    if path.is_empty() {
        std::ptr::null()
    } else {
        CString::new(path).expect("路径含 NUL").into_raw()
    }
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let wubi = args.first().cloned().unwrap_or_default();
    let chars = args.get(1).cloned().unwrap_or_default();
    let words = args.get(2).cloned().unwrap_or_default();
    let variant = args.get(3).cloned().unwrap_or_default();

    // SAFETY: 传入的是有效的 NUL 结尾 C 字符串或 NULL；返回值按契约检查。
    let session = unsafe { ime_session_new_with_data(c(&wubi), c(&chars), c(&words)) };
    if session.is_null() {
        eprintln!("加载失败：{wubi}");
        std::process::exit(1);
    }
    if !variant.is_empty() {
        // SAFETY: session 非空，path 有效。
        let _ = unsafe { ime_session_set_variant_data(session, c(&variant)) };
    }
    // 可选驻留：设 MEM_PROBE_HOLD 秒数后用 `vmmap` 量稳态物理足迹（而不是构造峰值）。
    if let Some(secs) = std::env::var("MEM_PROBE_HOLD")
        .ok()
        .and_then(|s| s.parse::<u64>().ok())
    {
        std::thread::sleep(std::time::Duration::from_secs(secs));
    }
    // SAFETY: session 由上面的构造函数返回且未释放。
    unsafe { ime_session_free(session) };
}
