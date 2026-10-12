//! 把拼音后端适配为 `ime_core::Engine`。

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

use crate::backend::PinyinBackend;
use std::sync::Arc;

/// 拼音引擎：把任意 [`PinyinBackend`] 适配到核心 [`Engine`] trait。
pub struct PinyinEngine {
    backend: Arc<dyn PinyinBackend>,
    max_code_len: usize,
    fuzzy: bool,
}

impl PinyinEngine {
    pub fn new(backend: Box<dyn PinyinBackend>, max_code_len: usize) -> Self {
        Self::new_shared(Arc::from(backend), max_code_len)
    }

    /// Share an immutable backend without sharing per-session options.
    pub fn new_shared(backend: Arc<dyn PinyinBackend>, max_code_len: usize) -> Self {
        Self {
            backend,
            max_code_len,
            fuzzy: false,
        }
    }
}

impl Engine for PinyinEngine {
    fn reverse_lookup(&self, text: &str) -> Option<String> {
        self.backend.reverse_lookup(text)
    }
    fn configure(&mut self, options: &ime_core::EngineOptions) {
        self.fuzzy = options.fuzzy;
    }
    fn convert(&self, input: &str, max: usize) -> ConvertResult {
        let mut forms = vec![input.to_string()];
        if self.fuzzy && input.len() <= 32 && input.bytes().all(|c| c.is_ascii_lowercase()) {
            let segmented = self.backend.segment(input);
            let parts = if segmented.is_empty() {
                vec![input.to_string()]
            } else {
                segmented
            };
            forms = vec![String::new()];
            for part in parts {
                let mut alternatives = vec![part.clone()];
                for (a, b) in [("zh", "z"), ("ch", "c"), ("sh", "s"), ("n", "l")] {
                    let changed = part
                        .strip_prefix(a)
                        .map(|tail| format!("{b}{tail}"))
                        .or_else(|| part.strip_prefix(b).map(|tail| format!("{a}{tail}")));
                    if let Some(form) = changed {
                        alternatives.push(form);
                    }
                }
                forms = forms
                    .iter()
                    .flat_map(|prefix| {
                        alternatives
                            .iter()
                            .map(move |part| format!("{prefix}{part}"))
                    })
                    .take(32)
                    .collect();
            }
        }
        let mut candidates: Vec<Candidate> = forms
            .iter()
            .flat_map(|form| {
                self.backend
                    .convert(form, max)
                    .into_iter()
                    .map(move |candidate| (candidate, form != input))
            })
            .map(|(pc, is_fuzzy)| Candidate {
                text: pc.text,
                code: pc.pinyin,
                weight: pc.weight,
                source: CandidateSource::Pinyin,
                comment: None,
                is_prefix: false,
                is_fuzzy,
            })
            .collect();
        candidates.sort_by(|a, b| {
            a.is_fuzzy
                .cmp(&b.is_fuzzy)
                .then_with(|| b.weight.cmp(&a.weight))
                .then_with(|| a.text.cmp(&b.text))
        });
        let mut seen = std::collections::HashSet::new();
        candidates.retain(|c| seen.insert(c.text.clone()));
        candidates.truncate(max);
        // 拼音绝不自动上屏（自动上屏仅限五笔精确唯一，见 技术方案 §2.3）。
        ConvertResult {
            candidates,
            should_commit: None,
        }
    }

    fn engine_type(&self) -> EngineType {
        EngineType::Pinyin
    }

    fn max_code_length(&self) -> usize {
        self.max_code_len
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::table::TablePinyinBackend;

    #[test]
    fn fuzzy_query_budget_is_bounded_for_many_ambiguous_syllables() {
        use std::sync::atomic::{AtomicUsize, Ordering};
        struct Backend(Arc<AtomicUsize>);
        impl PinyinBackend for Backend {
            fn name(&self) -> &'static str {
                "bounded-test"
            }
            fn segment(&self, input: &str) -> Vec<String> {
                input
                    .as_bytes()
                    .chunks(2)
                    .map(|_| "na".to_string())
                    .collect()
            }
            fn convert(&self, _: &str, _: usize) -> Vec<crate::PinyinCandidate> {
                self.0.fetch_add(1, Ordering::Relaxed);
                Vec::new()
            }
            fn reverse_lookup(&self, _: &str) -> Option<String> {
                None
            }
        }
        let calls = Arc::new(AtomicUsize::new(0));
        let mut engine = PinyinEngine::new(Box::new(Backend(Arc::clone(&calls))), 32);
        engine.configure(&ime_core::EngineOptions {
            fuzzy: true,
            auto_commit: false,
            z_wildcard: false,
        });
        engine.convert(&"na".repeat(16), 9);
        assert!(calls.load(Ordering::Relaxed) <= 32);
        calls.store(0, Ordering::Relaxed);
        engine.convert(&"na".repeat(17), 9);
        assert_eq!(calls.load(Ordering::Relaxed), 1);
    }

    fn engine() -> PinyinEngine {
        let chars = "wo\t我\t100\nni\t你\t90\nhao\t好\t80\n";
        let words = "ni hao\t你好\t200\n";
        PinyinEngine::new(
            Box::new(TablePinyinBackend::from_tsv(chars, words, "t").unwrap()),
            32,
        )
    }

    #[test]
    fn fuzzy_is_opt_in_and_deduplicated() {
        let backend = TablePinyinBackend::from_tsv("zang\t脏\t10\n", "", "fuzzy").unwrap();
        let mut e = PinyinEngine::new(Box::new(backend), 32);
        assert!(e.convert("zhang", 9).candidates.is_empty());
        e.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: false,
            fuzzy: true,
        });
        assert_eq!(e.convert("zhang", 9).candidates[0].text, "脏");
    }

    #[test]
    fn exact_spelling_precedes_frequent_fuzzy_matches_and_fuzzy_reaches_later_syllables() {
        let backend = TablePinyinBackend::from_tsv(
            "zhang\t张\t9\nzang\t脏\t1000\nshang\t上\t9\nsang\t桑\t1000\n",
            "zhang shang\t张上\t9\nzang sang\t脏桑\t1000\nzhang sang\t张桑\t1000\n",
            "quality",
        )
        .unwrap();
        let mut engine = PinyinEngine::new(Box::new(backend), 32);
        engine.configure(&ime_core::EngineOptions {
            fuzzy: true,
            auto_commit: false,
            z_wildcard: false,
        });
        let single = engine.convert("zhang", 9).candidates;
        assert_eq!(single[0].text, "张");
        assert!(!single[0].is_fuzzy);
        assert!(single.iter().any(|c| c.text == "脏" && c.is_fuzzy));
        let phrase = engine.convert("zhangshang", 9).candidates;
        assert_eq!(phrase[0].text, "张上");
        assert!(phrase.iter().any(|c| c.text == "张桑" && c.is_fuzzy));
        assert!(phrase.iter().any(|c| c.text == "脏桑" && c.is_fuzzy));
        assert_eq!(engine.convert("zhang", 1).candidates[0].text, "张");
        assert!(engine.convert("🙂", 9).candidates.is_empty());
    }

    #[test]
    fn convert_marks_source_pinyin() {
        let e = engine();
        let r = e.convert("nihao", 9);
        assert_eq!(r.candidates.first().unwrap().text, "你好");
        assert_eq!(
            r.candidates.first().unwrap().source,
            CandidateSource::Pinyin
        );
        assert_eq!(r.should_commit, None);
    }

    #[test]
    fn engine_type_is_pinyin() {
        assert_eq!(engine().engine_type(), EngineType::Pinyin);
        assert_eq!(engine().max_code_length(), 32);
    }
}
