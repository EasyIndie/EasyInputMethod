//! 把拼音后端适配为 `ime_core::Engine`。

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

use crate::backend::PinyinBackend;

/// 拼音引擎：把任意 [`PinyinBackend`] 适配到核心 [`Engine`] trait。
pub struct PinyinEngine {
    backend: Box<dyn PinyinBackend>,
    max_code_len: usize,
    fuzzy: bool,
}

impl PinyinEngine {
    pub fn new(backend: Box<dyn PinyinBackend>, max_code_len: usize) -> Self {
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
        if self.fuzzy {
            for (a, b) in [("zh", "z"), ("ch", "c"), ("sh", "s"), ("n", "l")] {
                for (from, to) in [(a, b), (b, a)] {
                    if let Some(tail) = input.strip_prefix(from) {
                        forms.push(format!("{to}{tail}"));
                    }
                }
            }
        }
        let mut candidates: Vec<Candidate> = forms
            .iter()
            .flat_map(|form| self.backend.convert(form, max))
            .map(|pc| Candidate {
                text: pc.text,
                code: pc.pinyin,
                weight: pc.weight,
                source: CandidateSource::Pinyin,
                comment: None,
                is_prefix: false,
            })
            .collect();
        candidates.sort_by(|a, b| b.weight.cmp(&a.weight).then_with(|| a.text.cmp(&b.text)));
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
