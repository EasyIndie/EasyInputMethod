//! 会话 ABI（`docs/技术方案.md` §5.3）。
//!
//! 不透明句柄 `ImeSession` 包装 [`ime_core::Session`]。默认用内置样本引擎（见
//! [`crate::samples`]）；[`ime_session_new_with_data`] 可从真实 TSV 数据文件加载。
//! 线程绑定：同一会话仅限单线程使用。
//!
//! 候选指针与缓冲区指针为借用，有效期至下一次会话变更
//! （`key` / `select` / `set_mode` / `reset` / `focus_out`）。

use std::ffi::{c_char, CString};
use std::ptr;

use ime_core::{CandidateSource, Engine, InputMode, KeyOutcome, Session};
use ime_pinyin::PinyinEngine;
use ime_table::CodeTableEngine;

use crate::error::{
    catch_ptr, catch_status, catch_value, cstr_arg, IME_ERR_INVALID_INPUT, IME_ERR_IO,
    IME_ERR_NULL, IME_OK,
};
use crate::samples;

/// 键被消费，候选已更新（与 `ime_session_key` 返回值一致）。
pub const IME_KEY_CONSUMED: i32 = 0;
/// 键触发了上屏，调用方应随后取 `ime_session_commit`。
pub const IME_KEY_COMMITTED: i32 = 1;
/// 键与本输入法无关，宿主应透传给系统。
pub const IME_KEY_PASS_THROUGH: i32 = 2;

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
    /// 组合缓冲区的 NUL 结尾视图（借用给 C/Swift），随会话变更刷新。
    ffi_buffer: Option<CString>,
    dictionary: Option<ime_dict::Store>,
    dictionary_error: i32,
    ffi_strings: Vec<(Option<CString>, Option<CString>)>,
}

fn source_to_int(source: CandidateSource) -> i32 {
    match source {
        CandidateSource::CodeTable => SOURCE_CODE_TABLE,
        CandidateSource::Pinyin => SOURCE_PINYIN,
        CandidateSource::Phrase => SOURCE_PHRASE,
    }
}

impl ImeSession {
    /// 用内置样本引擎创建会话（供 CLI 冒烟 / 无数据文件场景）。
    fn new() -> Box<ImeSession> {
        let wubi: Box<dyn Engine> = Box::new(CodeTableEngine::new(samples::wubi_table(), 4));
        let pinyin: Box<dyn Engine> =
            Box::new(PinyinEngine::new(Box::new(samples::pinyin_backend()), 32));
        ImeSession::from_engines(InputMode::Mixed, Some(wubi), Some(pinyin))
    }

    /// 组装会话并建立初始 FFI 视图。
    fn from_engines(
        mode: InputMode,
        wubi: Option<Box<dyn Engine>>,
        pinyin: Option<Box<dyn Engine>>,
    ) -> Box<ImeSession> {
        let mut session = Session::new(mode);
        if let Some(e) = wubi {
            session.set_wubi_engine(e);
        }
        if let Some(e) = pinyin {
            session.set_pinyin_engine(e);
        }
        let mut s = Box::new(ImeSession {
            session,
            ffi_candidates: Vec::new(),
            ffi_buffer: None,
            dictionary: None,
            dictionary_error: IME_OK,
            ffi_strings: Vec::new(),
        });
        s.refresh();
        s
    }

    fn ensure_dictionary(&mut self) {
        if self.dictionary.is_none() {
            match ime_dict::Store::load(crate::config::user_dictionary_path()) {
                Ok(store) => {
                    self.dictionary = Some(store);
                    self.dictionary_error = IME_OK;
                }
                Err(_) => {
                    self.dictionary_error = IME_ERR_IO;
                }
            }
        }
    }
    fn personalize(&mut self) {
        let Some(store) = self.dictionary.as_mut() else {
            return;
        };
        if store.refresh().is_err() {
            self.dictionary_error = IME_ERR_IO;
        }
        if !self.session.composing() {
            return;
        }
        let mode = self.session.mode();
        let buffer = self.session.buffer();
        let extra = store
            .entries()
            .iter()
            .filter(|((scheme, code, _), _)| {
                code.starts_with(buffer)
                    && (mode == InputMode::Mixed
                        || (mode == InputMode::WubiOnly && scheme == "wubi")
                        || (mode == InputMode::PinyinOnly && scheme == "pinyin"))
            })
            .map(|((scheme, code, text), _)| {
                let mut c = ime_core::Candidate::new(
                    text,
                    code,
                    0,
                    if scheme == "wubi" {
                        CandidateSource::CodeTable
                    } else {
                        CandidateSource::Pinyin
                    },
                );
                c.is_prefix = code != buffer;
                c
            })
            .collect();
        self.session.personalize(extra, |c| {
            let scheme = if c.source == CandidateSource::Pinyin {
                "pinyin"
            } else {
                "wubi"
            };
            let code: String = c.code.chars().filter(|c| !c.is_whitespace()).collect();
            store
                .entries()
                .get(&(scheme.into(), code, c.text.clone()))
                .copied()
                .unwrap_or(0)
        });
    }
    fn learn(&mut self, candidate: Option<ime_core::Candidate>) {
        let Some(c) = candidate else {
            return;
        };
        let Some(store) = self.dictionary.as_mut() else {
            return;
        };
        let scheme = if c.source == CandidateSource::Pinyin {
            "pinyin"
        } else {
            "wubi"
        };
        let code: String = c.code.chars().filter(|c| !c.is_whitespace()).collect();
        self.dictionary_error = if store.learn(scheme, &code, &c.text).is_ok() {
            IME_OK
        } else {
            IME_ERR_IO
        };
    }

    /// 由核心候选重建 FFI 视图（指针借用核心 `Candidate` 的字符串缓冲）。
    fn refresh(&mut self) {
        self.ffi_strings = self
            .session
            .candidates()
            .iter()
            .map(|c| {
                (
                    CString::new(c.text.as_str()).ok(),
                    CString::new(c.code.as_str()).ok(),
                )
            })
            .collect();
        let mut view: Vec<ImeCandidate> = Vec::with_capacity(self.session.candidates().len());
        for (c, (text, code)) in self.session.candidates().iter().zip(&self.ffi_strings) {
            view.push(ImeCandidate {
                text: text.as_ref().map_or(ptr::null(), |s| s.as_ptr()),
                code: code.as_ref().map_or(ptr::null(), |s| s.as_ptr()),
                weight: c.weight,
                source: source_to_int(c.source),
                is_prefix: i32::from(c.is_prefix),
            });
        }
        self.ffi_candidates = view;
        self.ffi_buffer = CString::new(self.session.buffer()).ok();
    }
}

/// 创建会话（内置样本引擎，`Mixed` 模式）；失败返回 `NULL`。
#[no_mangle]
pub extern "C" fn ime_session_new() -> *mut ImeSession {
    catch_ptr(|| Ok(Box::into_raw(ImeSession::new())))
}

/// 从真实数据文件创建会话（`Mixed` 模式）。
///
/// - `wubi_path`：五笔码表 TSV（必填，`code\ttext\tweight`）；
/// - `pinyin_chars_path`：拼音字表 TSV；为 `NULL` 时不启用拼音；
/// - `pinyin_words_path`：拼音词表 TSV；为 `NULL` 时只用字表（单音节）。
///
/// 任一路径非法、文件不存在或解析失败，返回 `NULL`（不 panic）。
#[no_mangle]
pub extern "C" fn ime_session_new_with_data(
    wubi_path: *const c_char,
    pinyin_chars_path: *const c_char,
    pinyin_words_path: *const c_char,
) -> *mut ImeSession {
    catch_ptr(|| {
        // SAFETY：契约见 `cstr_arg`。
        let wubi_path = unsafe { cstr_arg(wubi_path)? };
        let wubi: Box<dyn Engine> = Box::new(CodeTableEngine::new_shared(
            crate::data::wubi(wubi_path)?,
            4,
        ));
        let pinyin: Option<Box<dyn Engine>> = if pinyin_chars_path.is_null() {
            None
        } else {
            // SAFETY：契约见 `cstr_arg`（已确认非 NULL）。
            let chars = unsafe { cstr_arg(pinyin_chars_path)? };
            let words = if pinyin_words_path.is_null() {
                None
            } else {
                // SAFETY：同上。
                Some(unsafe { cstr_arg(pinyin_words_path)? })
            };
            Some(Box::new(PinyinEngine::new_shared(
                crate::data::pinyin(chars, words)?,
                32,
            )))
        };
        Ok(Box::into_raw(ImeSession::from_engines(
            InputMode::Mixed,
            Some(wubi),
            pinyin,
        )))
    })
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

/// 喂入一个 Unicode 码点（等价 `Session::handle_key`）。
///
/// 成功时返回 `IME_KEY_*`（`0` 消费 / `1` 上屏 / `2` 透传）；失败返回负数错误码。
#[no_mangle]
pub extern "C" fn ime_session_key(session: *mut ImeSession, codepoint: u32) -> i32 {
    catch_status(|| {
        // SAFETY：契约见模块注释（仅单线程使用）。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let ch = char::from_u32(codepoint).ok_or(IME_ERR_INVALID_INPUT)?;
        let selected = match ch {
            ' ' => s.session.candidates().first().cloned(),
            '1'..='9' => s
                .session
                .candidates()
                .get((ch as u8 - b'1') as usize)
                .cloned(),
            _ => None,
        };
        let outcome = s.session.handle_key(ch);
        if matches!(outcome, KeyOutcome::Committed(_)) {
            s.learn(selected);
        }
        s.personalize();
        s.refresh();
        Ok(match outcome {
            KeyOutcome::Consumed => IME_KEY_CONSUMED,
            KeyOutcome::Committed(_) => IME_KEY_COMMITTED,
            KeyOutcome::PassThrough => IME_KEY_PASS_THROUGH,
        })
    })
}

/// Apply engine options from the single configuration snapshot.
#[no_mangle]
pub extern "C" fn ime_session_configure(session: *mut ImeSession) -> i32 {
    catch_status(|| {
        // SAFETY: the caller owns a live session.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.ensure_dictionary();
        let cfg = crate::config::snapshot();
        let boolean = |key| cfg.get(key).and_then(|v| v.as_bool()).unwrap_or(false);
        s.session.set_input_options(
            boolean("input.full_width"),
            cfg.get("input.punctuation").and_then(|v| v.as_str()) == Some("chinese"),
        );
        s.session.configure_engines(&ime_core::EngineOptions {
            auto_commit: boolean("wubi.auto_commit"),
            fuzzy: boolean("pinyin.fuzzy"),
            z_wildcard: cfg.get("wubi.z_key").and_then(|v| v.as_str()) == Some("wildcard"),
        });
        Ok(IME_OK)
    })
}

#[no_mangle]
pub extern "C" fn ime_session_toggle_english(session: *mut ImeSession) -> i32 {
    catch_status(|| {
        // SAFETY: the caller owns a live session.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.toggle_english();
        s.refresh();
        Ok(IME_OK)
    })
}
#[no_mangle]
pub extern "C" fn ime_session_toggle_width(session: *mut ImeSession) -> i32 {
    catch_status(|| {
        // SAFETY: the caller owns a live session.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.toggle_width();
        s.refresh();
        Ok(IME_OK)
    })
}
#[no_mangle]
pub extern "C" fn ime_session_is_english(session: *mut ImeSession) -> i32 {
    catch_value(
        || {
            // SAFETY: the caller owns a live session.
            let s = unsafe { session.as_ref().ok_or(IME_ERR_NULL)? };
            Ok(i32::from(s.session.english()))
        },
        -1,
    )
}

/// Current session mode: mixed=0, wubi=1, pinyin=2.
#[no_mangle]
pub extern "C" fn ime_session_mode(session: *mut ImeSession) -> i32 {
    catch_value(
        || {
            // SAFETY: the caller owns a live session.
            let s = unsafe { session.as_ref().ok_or(IME_ERR_NULL)? };
            Ok(match s.session.mode() {
                InputMode::Mixed => 0,
                InputMode::WubiOnly => 1,
                InputMode::PinyinOnly => 2,
            })
        },
        -1,
    )
}

/// 取组合缓冲区（借用，NUL 结尾 UTF-8；下次会话变更前有效）。
/// `NULL` 会话返回 `NULL`。
#[no_mangle]
pub extern "C" fn ime_session_buffer(session: *mut ImeSession) -> *const c_char {
    catch_value(
        || {
            // SAFETY：契约见模块注释。
            let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
            Ok(s.ffi_buffer
                .as_ref()
                .map_or(ptr::null(), |c| c.as_ptr() as *const c_char))
        },
        ptr::null(),
    )
}

/// 切换输入模式（`"mixed"` / `"wubi"` / `"pinyin"`）；非法值返回
/// [`IME_ERR_INVALID_INPUT`]。切换会取消当前组合。
#[no_mangle]
pub extern "C" fn ime_session_set_mode(session: *mut ImeSession, mode: *const c_char) -> i32 {
    catch_status(|| {
        // SAFETY：契约见模块注释。
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        // SAFETY：契约见 `cstr_arg`。
        let mode = unsafe { cstr_arg(mode)? };
        let parsed: InputMode = mode.parse().map_err(|_| IME_ERR_INVALID_INPUT)?;
        s.session.set_mode(parsed);
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
        let selected = s.session.candidates().get(index as usize).cloned();
        if s.session.select(index as usize).is_none() {
            return Err(IME_ERR_INVALID_INPUT);
        }
        s.learn(selected);
        s.refresh();
        Ok(IME_OK)
    })
}

#[no_mangle]
pub extern "C" fn ime_session_dictionary_error(session: *mut ImeSession) -> i32 {
    catch_value(
        || {
            // SAFETY: the caller owns a live session.
            Ok(unsafe { session.as_ref().ok_or(IME_ERR_NULL)? }.dictionary_error)
        },
        IME_ERR_NULL,
    )
}

#[no_mangle]
pub extern "C" fn ime_session_dictionary_add(
    session: *mut ImeSession,
    scheme: *const c_char,
    code: *const c_char,
    text: *const c_char,
) -> i32 {
    catch_status(|| {
        // SAFETY: pointers follow the live-session and NUL-terminated input contracts.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let (scheme, code, text) = unsafe { (cstr_arg(scheme)?, cstr_arg(code)?, cstr_arg(text)?) };
        ime_dict::validate(scheme, code, text).map_err(|_| IME_ERR_INVALID_INPUT)?;
        s.ensure_dictionary();
        s.dictionary
            .as_mut()
            .ok_or(IME_ERR_IO)?
            .learn(scheme, code, text)
            .map_err(|_| IME_ERR_IO)?;
        s.personalize();
        s.refresh();
        Ok(IME_OK)
    })
}
#[no_mangle]
pub extern "C" fn ime_session_dictionary_import(
    session: *mut ImeSession,
    path: *const c_char,
) -> i32 {
    catch_status(|| {
        // SAFETY: pointers follow the live-session and NUL-terminated input contracts.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let path = std::path::Path::new(unsafe { cstr_arg(path)? });
        if !path.is_file() {
            return Err(IME_ERR_IO);
        }
        s.ensure_dictionary();
        s.dictionary
            .as_mut()
            .ok_or(IME_ERR_IO)?
            .import(path)
            .map_err(|_| IME_ERR_IO)?;
        s.personalize();
        s.refresh();
        Ok(IME_OK)
    })
}
#[no_mangle]
pub extern "C" fn ime_session_dictionary_export(
    session: *mut ImeSession,
    path: *const c_char,
) -> i32 {
    catch_status(|| {
        // SAFETY: pointers follow the live-session and NUL-terminated input contracts.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        let path = std::path::Path::new(unsafe { cstr_arg(path)? });
        let profile = crate::config::user_dictionary_path();
        let config = profile.with_file_name("config.toml");
        if path == config
            || path == profile
            || (path.exists()
                && (path.canonicalize().ok() == config.canonicalize().ok()
                    || path.canonicalize().ok() == profile.canonicalize().ok()))
        {
            return Err(IME_ERR_INVALID_INPUT);
        }
        s.ensure_dictionary();
        let store = s.dictionary.as_mut().ok_or(IME_ERR_IO)?;
        store.refresh().map_err(|_| IME_ERR_IO)?;
        store.export(path).map_err(|_| IME_ERR_IO)?;
        Ok(IME_OK)
    })
}

/// Move by a signed page delta; clamp at both ends.
#[no_mangle]
pub extern "C" fn ime_session_page(session: *mut ImeSession, delta: i32) -> i32 {
    catch_status(|| {
        // SAFETY: the caller owns a live, thread-bound session.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.page(delta);
        s.refresh();
        Ok(IME_OK)
    })
}

#[no_mangle]
pub extern "C" fn ime_session_set_page_size(session: *mut ImeSession, size: i32) -> i32 {
    catch_status(|| {
        if !(3..=9).contains(&size) {
            return Err(IME_ERR_INVALID_INPUT);
        }
        // SAFETY: the caller owns a live, thread-bound session.
        let s = unsafe { session.as_mut().ok_or(IME_ERR_NULL)? };
        s.session.set_page_size(size as usize);
        s.refresh();
        Ok(IME_OK)
    })
}

#[no_mangle]
pub extern "C" fn ime_session_page_index(session: *mut ImeSession) -> i32 {
    // SAFETY: a non-null pointer must be a live session, per the ABI contract.
    unsafe { session.as_ref() }.map_or(-1, |s| s.session.page_index() as i32)
}

#[no_mangle]
pub extern "C" fn ime_session_page_count(session: *mut ImeSession) -> i32 {
    // SAFETY: a non-null pointer must be a live session, per the ABI contract.
    unsafe { session.as_ref() }.map_or(-1, |s| s.session.page_count() as i32)
}

/// Read-only reverse lookup; NULL on invalid input, empty on unknown text.
#[no_mangle]
pub extern "C" fn ime_session_reverse_lookup(
    session: *const ImeSession,
    text: *const c_char,
) -> ImeString {
    catch_value(
        || {
            // SAFETY: callers supply a live session and a valid NUL-terminated string.
            let s = unsafe { session.as_ref().ok_or(IME_ERR_NULL)? };
            let text = unsafe { cstr_arg(text)? };
            if text.is_empty() || text.len() > 256 || text.chars().any(char::is_control) {
                return Err(IME_ERR_INVALID_INPUT);
            }
            Ok(owned_string(
                &s.session.reverse_lookup(text).unwrap_or_default(),
            ))
        },
        ImeString {
            data: ptr::null(),
            len: 0,
        },
    )
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
    use ime_table::Table;
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
    fn reverse_lookup_is_owned_read_only_and_handles_invalid_input() {
        let s = ime_session_new();
        assert!(!s.is_null());
        assert_eq!(ime_session_key(s, 'w' as u32), IME_KEY_CONSUMED);
        let before = ime_session_candidates(s);
        let query = CString::new("你好").unwrap();
        let reading = ime_session_reverse_lookup(s, query.as_ptr());
        assert_eq!(unsafe { cstr(reading.data) }, Some("ni hao"));
        assert_eq!(ime_session_candidates(s).items, before.items);
        let unknown = CString::new("🙂").unwrap();
        let empty = ime_session_reverse_lookup(s, unknown.as_ptr());
        assert_eq!(unsafe { cstr(empty.data) }, Some(""));
        let invalid = CString::new("a".repeat(257)).unwrap();
        assert!(ime_session_reverse_lookup(s, invalid.as_ptr())
            .data
            .is_null());
        assert!(ime_session_reverse_lookup(ptr::null(), query.as_ptr())
            .data
            .is_null());
        assert!(ime_session_reverse_lookup(s, ptr::null()).data.is_null());
        ime_session_free(s);
        // The owned result remains valid after its session is destroyed.
        assert_eq!(unsafe { cstr(reading.data) }, Some("ni hao"));
        ime_string_free(reading);
        ime_string_free(empty);
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
    fn candidate_strings_are_terminated_and_owned_across_pages() {
        let mut table = Table::new();
        for i in 0..20 {
            table.insert("ab", &format!("候选词语{i:02}"), 100 - i);
        }
        table.finalize();
        let boxed = ImeSession::from_engines(
            InputMode::WubiOnly,
            Some(Box::new(CodeTableEngine::new(table, 4))),
            None,
        );
        let s = Box::into_raw(boxed);
        assert_eq!(ime_session_set_page_size(s, 7), IME_OK);
        assert_eq!(ime_session_set_page_size(s, 10), IME_ERR_INVALID_INPUT);
        ime_session_key(s, 'a' as u32);
        ime_session_key(s, 'b' as u32);
        assert_eq!(ime_session_page_count(s), 3);
        assert_eq!(ime_session_page(s, 1), IME_OK);
        let list = ime_session_candidates(s);
        assert_eq!(list.len, 7);
        // SAFETY: list strings are borrowed from a live session until the next mutation.
        let first = unsafe { &*list.items };
        assert_eq!(
            unsafe { std::ffi::CStr::from_ptr(first.text) }
                .to_str()
                .unwrap(),
            "候选词语07"
        );
        assert_eq!(
            unsafe { std::ffi::CStr::from_ptr(first.code) }.to_bytes(),
            b"ab"
        );
        assert_eq!(ime_session_select(s, 1), IME_OK);
        let committed = ime_session_commit(s);
        assert_eq!(
            unsafe { std::ffi::CStr::from_ptr(committed.data) }
                .to_str()
                .unwrap(),
            "候选词语08"
        );
        ime_string_free(committed);
        ime_session_free(s);
    }

    #[test]
    fn page_without_composition_is_safe() {
        let s = ime_session_new();
        assert_eq!(ime_session_page(s, 1), IME_OK);
        assert_eq!(ime_session_page(s, -1), IME_OK);
        ime_session_free(s);
    }

    #[test]
    fn key_outcome_and_buffer() {
        let s = ime_session_new();
        assert_eq!(ime_session_key(s, 'w' as u32), IME_KEY_CONSUMED);
        assert_eq!(ime_session_key(s, 'q' as u32), IME_KEY_CONSUMED);
        // SAFETY：缓冲指针借自会话，测试期间有效。
        unsafe { assert_eq!(cstr(ime_session_buffer(s)), Some("wq")) };

        // 空格上屏首个候选。
        assert_eq!(ime_session_key(s, ' ' as u32), IME_KEY_COMMITTED);
        // SAFETY：同上。
        unsafe { assert_eq!(cstr(ime_session_buffer(s)), Some("")) };

        // 与输入法无关的键透传。
        assert_eq!(ime_session_key(s, '@' as u32), IME_KEY_PASS_THROUGH);
        ime_session_free(s);
    }

    #[test]
    fn set_mode_validates_and_switches() {
        let s = ime_session_new();
        let pinyin = CString::new("pinyin").unwrap();
        assert_eq!(ime_session_set_mode(s, pinyin.as_ptr()), IME_OK);
        for ch in "nihao".chars() {
            ime_session_key(s, ch as u32);
        }
        let cands = ime_session_candidates(s);
        assert!(cands.len >= 1);
        // SAFETY：候选指针借自会话，测试期间有效。
        unsafe { assert_eq!(cstr((*cands.items).text), Some("你好")) };

        let bad = CString::new("klingon").unwrap();
        assert_eq!(ime_session_set_mode(s, bad.as_ptr()), IME_ERR_INVALID_INPUT);
        assert_eq!(ime_session_set_mode(s, ptr::null()), IME_ERR_NULL);
        ime_session_free(s);
    }

    #[test]
    fn new_with_data_loads_tsv() {
        let dir = std::env::temp_dir();
        let tag = format!("ime-ffi-data-{}", std::process::id());
        let wubi_path = dir.join(format!("{tag}-wubi.tsv"));
        let chars_path = dir.join(format!("{tag}-chars.tsv"));
        let words_path = dir.join(format!("{tag}-words.tsv"));
        std::fs::write(&wubi_path, "wq\t你\t100\nkwwl\t中华人民共和国\t90\n").unwrap();
        std::fs::write(&chars_path, "ni\t你\t90\nhao\t好\t80\n").unwrap();
        std::fs::write(&words_path, "ni hao\t你好\t200\n").unwrap();

        let wubi = CString::new(wubi_path.to_str().unwrap()).unwrap();
        let chars = CString::new(chars_path.to_str().unwrap()).unwrap();
        let words = CString::new(words_path.to_str().unwrap()).unwrap();
        let s = ime_session_new_with_data(wubi.as_ptr(), chars.as_ptr(), words.as_ptr());
        assert!(!s.is_null());
        assert_eq!(ime_session_key(s, 'w' as u32), IME_KEY_CONSUMED);
        assert_eq!(ime_session_key(s, 'q' as u32), IME_KEY_CONSUMED);
        let cands = ime_session_candidates(s);
        assert!(cands.len >= 1);
        // SAFETY：候选指针借自会话，测试期间有效。
        unsafe { assert_eq!(cstr((*cands.items).text), Some("你")) };
        ime_session_free(s);

        for path in [&wubi_path, &chars_path, &words_path] {
            let _ = std::fs::remove_file(path);
        }
    }

    #[test]
    fn new_with_data_missing_file_returns_null() {
        let missing = CString::new("/nonexistent/ime-ffi-nope.tsv").unwrap();
        let s = ime_session_new_with_data(missing.as_ptr(), ptr::null(), ptr::null());
        assert!(s.is_null());
        // 空指针路径同样返回 NULL（不 panic）。
        assert!(ime_session_new_with_data(ptr::null(), ptr::null(), ptr::null()).is_null());
    }
}
