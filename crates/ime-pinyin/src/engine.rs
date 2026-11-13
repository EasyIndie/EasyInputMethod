//! 把拼音后端适配为 `ime_core::Engine`。

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

use crate::backend::PinyinBackend;
use std::sync::Arc;

/// 拼音引擎：把任意 [`PinyinBackend`] 适配到核心 [`Engine`] trait。
pub struct PinyinEngine {
    backend: Arc<dyn PinyinBackend>,
    max_code_len: usize,
    fuzzy: bool,
    /// 把输入按小鹤双拼解释（ADR-336）。
    double: bool,
    /// 本地时间（自 epoch 起的本地秒）；用于日期/时间候选（ADR-342）。
    now: Option<i64>,
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
            double: false,
            now: None,
        }
    }
}

impl PinyinEngine {
    /// 双拼：把按键展开成全拼再查；分段候选的覆盖长度从「全拼字节」换算回「按键数」。
    ///
    /// 展开不出合法音节就不出候选（不猜）；双拼下不叠加模糊音。
    fn convert_double(&self, input: &str, max: usize) -> ConvertResult {
        let valid = |s: &str| self.backend.segment(s).as_slice() == [s.to_string()];
        let Some(expanded) = crate::double::expand(input, &valid) else {
            return ConvertResult::default();
        };
        let candidates = self
            .backend
            .convert(&expanded.full, max)
            .into_iter()
            .filter_map(|pc| {
                let consumed = match pc.consumed {
                    0 => 0,
                    bytes => expanded.keys_for(bytes)?,
                };
                Some(Candidate {
                    text: pc.text,
                    code: pc.pinyin,
                    weight: pc.weight,
                    source: CandidateSource::Pinyin,
                    comment: None,
                    is_prefix: pc.is_completion,
                    is_fuzzy: false,
                    consumed,
                })
            })
            .collect();
        ConvertResult {
            candidates,
            should_commit: None,
        }
    }
}

impl PinyinEngine {
    /// 日期 / 时间 / 星期候选（ADR-342）：只响应全拼的精确键名，双拼与模糊音都不参与。
    fn dynamic_candidates(&self, input: &str, max: usize) -> Option<Vec<Candidate>> {
        let now = self.now?;
        let text = match input {
            "riqi" => {
                let (year, month, day) = civil_from_days(now.div_euclid(86_400));
                format!("{year}年{month}月{day}日")
            }
            "shijian" => {
                let seconds = now.rem_euclid(86_400);
                format!("{:02}:{:02}", seconds / 3_600, seconds % 3_600 / 60)
            }
            "xingqi" => {
                let weekday = (now.div_euclid(86_400) + 4).rem_euclid(7) as usize;
                let names = ["日", "一", "二", "三", "四", "五", "六"];
                format!("星期{}", names[weekday])
            }
            _ => return None,
        };
        (max > 0).then(|| {
            vec![Candidate::new(
                text,
                input,
                10_000,
                CandidateSource::Dynamic,
            )]
        })
    }
}

/// 把「自 1970-01-01 起的天数」换算成年月日（Howard Hinnant 的 civil_from_days）。
fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = mp + if mp < 10 { 3 } else { -9 };
    (year + i64::from(month <= 2), month, day)
}

impl Engine for PinyinEngine {
    fn reverse_lookup(&self, text: &str) -> Option<String> {
        self.backend.reverse_lookup(text)
    }
    fn configure(&mut self, options: &ime_core::EngineOptions) {
        self.fuzzy = options.fuzzy;
        self.double = options.double_pinyin;
    }
    fn set_now(&mut self, local_seconds: Option<i64>) {
        self.now = local_seconds;
    }
    fn convert(&self, input: &str, max: usize) -> ConvertResult {
        if self.double {
            return self.convert_double(input, max);
        }
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
            // 模糊音改写后的拼写与用户输入不等长，分段候选的字节偏移对不上，丢弃。
            .filter(|(candidate, is_fuzzy)| !(*is_fuzzy && candidate.consumed > 0))
            .map(|(pc, is_fuzzy)| Candidate {
                text: pc.text,
                code: pc.pinyin,
                weight: pc.weight,
                source: CandidateSource::Pinyin,
                comment: None,
                is_prefix: pc.is_completion,
                consumed: pc.consumed,
                is_fuzzy,
            })
            .collect();
        candidates.sort_by(|a, b| {
            a.class()
                .cmp(&b.class())
                .then_with(|| a.is_fuzzy.cmp(&b.is_fuzzy))
                .then_with(|| b.weight.cmp(&a.weight))
                .then_with(|| a.text.cmp(&b.text))
        });
        if let Some(dynamic) = self.dynamic_candidates(input, max) {
            candidates.extend(dynamic);
            candidates.sort_by(|a, b| {
                a.class()
                    .cmp(&b.class())
                    .then_with(|| a.is_fuzzy.cmp(&b.is_fuzzy))
                    .then_with(|| b.weight.cmp(&a.weight))
                    .then_with(|| a.text.cmp(&b.text))
            });
        }
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
            double_pinyin: false,
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
    fn dynamic_date_time_and_weekday_candidates_come_from_the_supplied_clock() {
        let mut e = engine();
        assert!(
            e.convert("riqi", 9).candidates.is_empty(),
            "no clock, no dynamic candidate"
        );
        e.set_now(Some(1_794_573_240)); // 2026-11-13 12:34:00 UTC
        let date = e.convert("riqi", 9).candidates;
        assert_eq!(date[0].text, "2026年11月13日");
        assert_eq!(date[0].source, CandidateSource::Dynamic);
        assert_eq!(e.convert("shijian", 9).candidates[0].text, "12:34");
        assert_eq!(e.convert("xingqi", 9).candidates[0].text, "星期五");
        // 双拼按键不按全拼解释，不生成环境候选。
        let mut double = engine();
        double.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: false,
            fuzzy: false,
            double_pinyin: true,
        });
        double.set_now(Some(1_794_573_240));
        assert!(double.convert("riqi", 9).candidates.is_empty());
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
            double_pinyin: false,
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
            double_pinyin: false,
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
    fn double_pinyin_expands_keys_and_reports_partials_in_keys() {
        let backend = TablePinyinBackend::from_tsv(
            "ni\t你\t900\nhao\t好\t700\nshi\t是\t950\njie\t界\t600\n",
            "ni hao\t你好\t50\nshi jie\t世界\t60\n",
            "double",
        )
        .unwrap();
        let mut e = PinyinEngine::new(Box::new(backend), 32);
        // 关着的时候 `nihc` 不是合法全拼：没有覆盖整串的候选。
        assert!(e
            .convert("nihc", 9)
            .candidates
            .iter()
            .all(|c| c.consumed > 0));
        e.configure(&ime_core::EngineOptions {
            fuzzy: true,
            auto_commit: false,
            z_wildcard: false,
            double_pinyin: true,
        });
        assert_eq!(e.convert("nihc", 9).candidates[0].text, "你好");
        let long = e.convert("nihcuijp", 9).candidates;
        assert_eq!(long[0].text, "你好世界");
        // 「你好」覆盖 2 个音节 = 4 个按键（全拼上是 5 个字节）。
        let front = long.iter().find(|c| c.text == "你好").unwrap();
        assert_eq!(front.consumed, 4);
        assert_eq!(long.iter().find(|c| c.text == "你").unwrap().consumed, 2);
        // 拼不出合法音节：不出候选，也不回退成全拼解释。
        assert!(e.convert("nihao", 9).candidates.is_empty());
        assert_eq!(e.convert("nihc", 9).should_commit, None);
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
