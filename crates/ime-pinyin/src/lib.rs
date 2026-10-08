//! 萤火虫输入法拼音引擎：可插拔后端 + 内置轻量兜底。
//!
//! 纯逻辑、零 IO、零网络；`#![forbid(unsafe_code)]`。
//!
//! - [`PinyinBackend`]：可插拔后端 trait（ADR-008 §8.1）；
//! - [`TablePinyinBackend`]：基于内存表的内置轻量兜底（音节→高频字词表 + 简拼）；
//! - [`PinyinEngine`]：把后端适配到 `ime_core::Engine`。
//!
//! 数据由 `crates/ime-pinyin/examples/generate.rs` 离线生成（D5/D4/D10，均 MIT），
//! 见 `data/generated/pinyin-chars.tsv` 与 `pinyin-words.tsv`。

#![forbid(unsafe_code)]

mod backend;
mod engine;
mod syllable;
mod table;

pub use backend::{PinyinBackend, PinyinCandidate};
pub use engine::PinyinEngine;
pub use syllable::{segment, strip_tones, tone_base, MAX_SYLLABLE_LEN};
pub use table::{TablePinyinBackend, TsvError};
