//! 会话 ABI（`docs/技术方案.md` §5.3）。
//!
//! 不透明句柄 `ImeSession` 包装 [`ime_core::Session`]，内置样本引擎（见
//! [`crate::samples`]）。线程绑定：同一会话仅限单线程使用。
//!
//! 候选指针为借用，有效期至下一次会话变更（`key` / `select` / `reset` / `focus_out`）。

use std::ffi::{c_char, CString};
use std::ptr;

use ime_core::{CandidateSource, InputMode, Session};
use ime_pinyin::PinyinEngine;
use ime_table::CodeTableEngine;

use crate::error::{
    catch_ptr, catch_status, catch_value, IME_ERR_INVALID_INPUT, IME_ERR_NULL, IME_OK,
};
use crate::samples;

/// 候选来源（与 C 头文件 `IME_SOURCE_*` 一致）。
const SOURCE_CODE_TABLE: i32 = 0;
const SOURCE_PINYIN: i32 = 1;
const SOURCE_PHRASE: i32 = 2;

/// 库所有的 UTF-8 字符串（调用方负责 [`ime_string_free`]）。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeString {
    /// NUL 结尾 UTF-8；空串为 `""`，绝不 `NULL`。
    pub data: *const c_char,
    /// 字节长度（不含结尾 NUL）。
    pub len: u32,
}

/// 一个候选（借用自会话）。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeCandidate {
    /// 候选文本（UTF-8）。
    pub text: *const c_char,
    /// 五笔码或拼音（UTF-8）。
    pub code: *const c_char,
    pub weight: i32,
    /// [`CandidateSource`] 映射：0=码表、1=拼音、2=词组。
    pub source: i32,
    /// 是否为前缀预测候选（0/1）。
    pub is_prefix: i32,
}

/// 候选列表（借用自会话，见模块注释）。
#[repr(C)]
#[derive(Clone, Copy)]
pub struct ImeCandidates {
    pub items: *const ImeCandidate,
    pub len: u32,
}

/// 会话句柄（不透明）。
pub struct ImeSession {
    session: Session,
    /// 会话候选的 FFI 视图；`text`/`code` 指针指向 `session` 内的字符串，
    /// 在下次会话变更前保持有效。
    ffi_candidates: Vec<ImeCandidate>,
}

fn source_to_int(source: CandidateSource) -> i32 {
    match source {
        CandidateSource::CodeTable => SOURCE_CODE_TABLE,
        CandidateSource::Pinyin => SOURCE_PINYIN,
        CandidateSource::Phrase => SOURCE_PHRASE,
    }
}

impl ImeSession {
    fn new() -> Box<ImeSession> {
        let mut session = Session::new(InputMode::Mixed);
        session.set_wubi_engine(Box::new(CodeTableEngine::new(samples::wubi_table(), 4)));
        session.set_pinyin_engine(Box::new(PinyinEngine::new(
            Box::new(samples::pinyin_backend()),
            32,
        )));
        Box::new(ImeSession {
            session,
            ffi_candidates: Vec::new(),
        })
    }

    /// 由核心候选重建 FFI 视图（指针借用核心 `Candidate` 的字符串缓冲）。
    fn refresh(&mut self) {
        let mut view: Vec<ImeCandidate> = Vec::with_capacity(self.session.candidates().len());
        for c in self.session.candidates() {
            view.push(ImeCandidate {
                text: c.text.as_ptr() as *const c_char,
                code: c.code.as_ptr() as *const c_char,
                weight: c.weight,
                source: source_to_int(c.source),
                is_prefix: i32::from(c.is_prefix),
            });
        }
        self.ffi_candidates = view;
    }
}

/// 创建会话（内置样本引擎，`Mixed` 模式）；失败返回 `NULL`。
#[no_mangle]
pub extern "C" fn ime_session_new() -> *mut ImeSession {
    catch_ptr(|| Ok(Box::into_raw(ImeSession::new())))
}

/// 释放会话；`NULL` 为安全 no-op。
#[no_mangle]
pub extern "C" fn ime_session_free(session: *mut ImeSession) {
    if session.is_null() {
        return;
    }
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY：指针由 `ime_session_new` 产生，且调用方保证只释放一次。
        unsafe { drop(Box::from_raw(session)) };
    }));
}

/// 喂入一个 Unicode 码点（等价 `Session::handle_key`）。返回错误码。
#[no_mangle]
pub extern "C" fn ime_session_key(session: *mut ImeSession, codepoint: u32) -> i32 {
    catch_status(|| {
        // SAFETY：契约见模块注释（仅单线程使用）。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let ch = char::from_u32(codepoint).ok_or(IME_ERR_INVALID_INPUT)?;
        let _ = s.session.handle_key(ch);
        s.refresh();
        Ok(IME_OK)
    })
}

/// 取当前候选（借用）；`NULL` 会话或 panic 时返回空列表。
#[no_mangle]
pub extern "C" fn ime_session_candidates(session: *mut ImeSession) -> ImeCandidates {
    catch_value(
        || {
            // SAFETY：契约见模块注释。
            let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
            Ok(ImeCandidates {
                items: s.ffi_candidates.as_ptr(),
                len: s.ffi_candidates.len() as u32,
            })
        },
        ImeCandidates {
            items: ptr::null(),
            len: 0,
        },
    )
}

/// 选择第 `index` 个候选并上屏；越界返回 [`IME_ERR_INVALID_INPUT`]。
#[no_mangle]
pub extern "C" fn ime_session_select(session: *mut ImeSession, index: i32) -> i32 {
    catch_status(|| {
        // SAFETY：契约见模块注释。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        if index < 0 {
            return Err(IME_ERR_INVALID_INPUT);
        }
        if s.session.select(index as usize).is_none() {
            return Err(IME_ERR_INVALID_INPUT);
        }
        s.refresh();
        Ok(IME_OK)
    })
}

/// 候选翻页。候选窗翻页状态属宿主（P1-M4）；`ime-core` 目前固定每页
/// 最多 9 条候选、无跨页状态，故本入口保留 ABI 稳定、暂为 no-op。
#[no_mangle]
pub extern "C" fn ime_session_page(session: *mut ImeSession, _delta: i32) -> i32 {
    catch_status(|| {
        // SAFETY：契约见模块注释。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let _ = s;
        Ok(IME_OK)
    })
}

/// 取已上屏文本（库分配，调用方负责 [`ime_string_free`]）。
#[no_mangle]
pub extern "C" fn ime_session_commit(session: *mut ImeSession) -> ImeString {
    catch_value(
        || {
            // SAFETY：契约见模块注释。
            let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
            Ok(owned_string(s.session.committed()))
        },
        ImeString {
            data: ptr::null(),
            len: 0,
        },
    )
}

/// 失焦：取消当前组合，不改变模式。
#[no_mangle]
pub extern "C" fn ime_session_focus_out(session: *mut ImeSession) {
    let _ = catch_status(|| {
        // SAFETY：契约见模块注释。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.cancel();
        s.refresh();
        Ok(IME_OK)
    });
}

/// 复位：取消当前组合。
#[no_mangle]
pub extern "C" fn ime_session_reset(session: *mut ImeSession) {
    let _ = catch_status(|| {
        // SAFETY：契约见模块注释。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.cancel();
        s.refresh();
        Ok(IME_OK)
    });
}

/// 释放 [`ImeString`]（对应 `ime_session_commit` 的返回值）；`NULL` 为安全 no-op。
#[no_mangle]
pub extern "C" fn ime_string_free(s: ImeString) {
    if s.data.is_null() {
        return;
    }
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        // SAFETY：指针由 `owned_string` 经 `CString::into_raw` 产生，所有权唯一。
        unsafe { drop(CString::from_raw(s.data as *mut c_char)) };
    }));
}

/// 把 `&str` 复制为调用方所有的 [`ImeString`]。
fn owned_string(text: &str) -> ImeString {
    match CString::new(text) {
        Ok(c) => {
            let len = c.as_bytes().len() as u32;
            ImeString {
                data: c.into_raw(),
                len,
            }
        }
        Err(_) => ImeString {
            data: ptr::null(),
            len: 0,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    /// 测试辅助：把候选 `text` 指针读成 `&str`（内部使用，仅测试）。
    unsafe fn cstr<'a>(ptr: *const c_char) -> Option<&'a str> {
        if ptr.is_null() {
            return None;
        }
        // SAFETY：指针来自会话内部字符串，测试期间保持有效。
        unsafe { CStr::from_ptr(ptr) }.to_str().ok()
    }

    #[test]
    fn create_key_candidates_select_commit() {
        let s = ime_session_new();
        assert!(!s.is_null());

        assert_eq!(ime_session_key(s, 'w' as u32), IME_OK);
        assert_eq!(ime_session_key(s, 'q' as u32), IME_OK);

        let cands = ime_session_candidates(s);
        assert!(cands.len >= 1);
        // SAFETY：候选指针借自会话，测试期间保持有效。
        unsafe {
            assert_eq!(cstr((*cands.items).text), Some("你"));
            assert_eq!(cstr((*cands.items).code), Some("wq"));
        }

        assert_eq!(ime_session_select(s, 0), IME_OK);
        let committed = ime_session_commit(s);
        // SAFETY：commit 指针在 ime_string_free 前有效。
        unsafe {
            assert_eq!(cstr(committed.data), Some("你"));
        }
        ime_string_free(committed);

        ime_session_free(s);
    }

    #[test]
    fn null_session_is_safe() {
        assert_eq!(ime_session_key(ptr::null_mut(), 'a' as u32), IME_ERR_NULL);
        let cands = ime_session_candidates(ptr::null_mut());
        assert_eq!(cands.len, 0);
        assert!(cands.items.is_null());
        ime_session_select(ptr::null_mut(), 0); // 返回错误码，不崩
        ime_session_focus_out(ptr::null_mut()); // 无返回值，不崩
        ime_session_free(ptr::null_mut());
        ime_string_free(ImeString {
            data: ptr::null(),
            len: 0,
        });
    }

    #[test]
    fn invalid_codepoint_returns_error() {
        let s = ime_session_new();
        // 超出 Unicode 范围与代理区。
        assert_eq!(ime_session_key(s, 0x11_0000), IME_ERR_INVALID_INPUT);
        assert_eq!(ime_session_key(s, 0xD800), IME_ERR_INVALID_INPUT);
        ime_session_free(s);
    }

    #[test]
    fn select_out_of_range_returns_error() {
        let s = ime_session_new();
        assert_eq!(ime_session_key(s, 'k' as u32), IME_OK);
        assert_eq!(ime_session_select(s, 99), IME_ERR_INVALID_INPUT);
        assert_eq!(ime_session_select(s, -1), IME_ERR_INVALID_INPUT);
        ime_session_free(s);
    }

    #[test]
    fn page_is_safe_noop_for_now() {
        let s = ime_session_new();
        assert_eq!(ime_session_page(s, 1), IME_OK);
        assert_eq!(ime_session_page(s, -1), IME_OK);
        ime_session_free(s);
    }
}
