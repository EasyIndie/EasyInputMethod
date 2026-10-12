//! 错误码与 `catch_unwind` / C 字符串边界防护。
//!
//! FFI 返回值约定：`0` 成功，负数错误；返回指针的函数用 `NULL` 表示错误；
//! 返回结构体数组的函数用空数组表示错误。

use std::ffi::{c_char, CStr};
use std::panic::{catch_unwind, AssertUnwindSafe};

/// 成功。
pub const IME_OK: i32 = 0;
/// 空指针参数。
pub const IME_ERR_NULL: i32 = -1;
/// 非法 UTF-8。
pub const IME_ERR_INVALID_UTF8: i32 = -2;
/// 值非法（类型 / 范围 / 枚举）。
pub const IME_ERR_INVALID_INPUT: i32 = -3;
/// 未知配置键。
pub const IME_ERR_UNKNOWN_KEY: i32 = -4;
/// 文件 IO 错误。
pub const IME_ERR_IO: i32 = -5;
/// 语法 / 解析错误。
pub const IME_ERR_PARSE: i32 = -6;
/// 配置文件被并发写者锁定。
pub const IME_ERR_LOCKED: i32 = -7;
/// 内部 panic（`catch_unwind` 兜底，绝不应出现）。
pub const IME_ERR_PANIC: i32 = -8;
/// The exact user entry does not exist.
pub const IME_ERR_NOT_FOUND: i32 = -9;

/// 兜底执行：任何 panic 都转为 [`IME_ERR_PANIC`]。
pub fn catch_status<F>(f: F) -> i32
where
    F: FnOnce() -> Result<i32, i32>,
{
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(code)) => code,
        Ok(Err(code)) => code,
        Err(_) => IME_ERR_PANIC,
    }
}

/// 兜底执行返回指针的闭包：任何 panic / 错误都转为 `NULL`。
pub fn catch_ptr<F, T>(f: F) -> *mut T
where
    F: FnOnce() -> Result<*mut T, i32>,
{
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(ptr)) => ptr,
        Ok(Err(_)) | Err(_) => std::ptr::null_mut(),
    }
}

/// 兜底执行返回可复制值的闭包：任何 panic / 错误都转为 `fallback`。
pub fn catch_value<T, F>(f: F, fallback: T) -> T
where
    T: Copy,
    F: FnOnce() -> Result<T, i32>,
{
    match catch_unwind(AssertUnwindSafe(f)) {
        Ok(Ok(v)) => v,
        Ok(Err(_)) | Err(_) => fallback,
    }
}

/// 读取一个 C 字符串参数；`NULL` 返回 [`IME_ERR_NULL`]，非法 UTF-8 返回
/// [`IME_ERR_INVALID_UTF8`]。
///
/// # Safety
///
/// 指针若非 `NULL`，必须指向以 NUL 结尾、且在其生命周期内有效的 C 字符串。
pub unsafe fn cstr_arg<'a>(ptr: *const c_char) -> Result<&'a str, i32> {
    if ptr.is_null() {
        return Err(IME_ERR_NULL);
    }
    // SAFETY：契约由调用方保证（见上方 # Safety）。
    let c = unsafe { CStr::from_ptr(ptr) };
    c.to_str().map_err(|_| IME_ERR_INVALID_UTF8)
}
