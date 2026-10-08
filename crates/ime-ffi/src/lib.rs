//! 萤火虫输入法窄 C ABI（唯一 `unsafe` 集中地）。
//!
//! 会话 ABI 见 `docs/技术方案.md` §5.3；配置 ABI 见 `docs/配置架构.md` §9。
//!
//! 硬契约：
//! - 绝不 panic 穿越 FFI：所有入口 `catch_unwind` 兜底，返回错误码 / NULL / 空候选；
//! - 纯 C、不透明句柄、UTF-8、错误用 `int32_t` 返回码；
//! - 本 crate 是唯一允许 `unsafe` 的地方（其它 crate 仍 `forbid(unsafe_code)`）；
//! - 不联网（`verify-no-network` 仍须通过）。

#![deny(unsafe_op_in_unsafe_fn)]

mod config;
mod error;
mod samples;
mod session;

pub use error::{
    IME_ERR_INVALID_INPUT, IME_ERR_INVALID_UTF8, IME_ERR_IO, IME_ERR_LOCKED, IME_ERR_NULL,
    IME_ERR_PANIC, IME_ERR_PARSE, IME_ERR_UNKNOWN_KEY, IME_OK,
};
