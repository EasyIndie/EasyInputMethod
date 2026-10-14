//! 内存表拼音后端（内置轻量兜底，零外部依赖）。

use std::collections::{HashMap, HashSet};
use std::error::Error;
use std::fmt;
use std::sync::Arc;

use crate::backend::{PinyinBackend, PinyinCandidate};
use crate::syllable::segment;

/// 解析拼音 TSV（`data/generated/pinyin-chars.tsv` / `pinyin-words.tsv`）时的错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TsvError {
    /// 行缺列（chars 表应 3 列、words 表应 3 列，且音节/文本非空）。
    MissingColumn { line: usize },
    /// weight 不是合法整数。
    InvalidWeight { line: usize, value: String },
    /// 音节/拼音字段含非 ASCII 小写字母。
    InvalidSyllable { line: usize, value: String },
}

impl fmt::Display for TsvError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TsvError::MissingColumn { line } => {
                write!(f, "第 {line} 行缺列（应为 code\\ttext\\tweight）")
            }
            TsvError::InvalidWeight { line, value } => {
                write!(f, "第 {line} 行权重非法：{value}")
            }
            TsvError::InvalidSyllable { line, value } => {
                write!(f, "第 {line} 行拼音/音节非法：{value}")
            }
        }
    }
}

impl Error for TsvError {}

/// 基于内存表的轻量拼音兜底。
///
/// 数据来源：`data/generated/pinyin-chars.tsv`（`音节\t字\tweight`）与
/// `data/generated/pinyin-words.tsv`（`拼音(空格分隔)\t词\tweight`）。
#[derive(Debug, Default)]
pub struct TablePinyinBackend {
    name: &'static str,
    /// 音节 → [(字, weight)]，组内按权重降序。
    chars: HashMap<String, Vec<(char, i32)>>,
    /// 归一化拼音（空格分隔）→ [(词, weight)]。
    words: HashMap<String, Vec<(Arc<str>, i32)>>,
    /// 首字母串（简拼键）→ [(词, weight)]。
    initials: HashMap<String, Vec<(Arc<str>, i32)>>,
    /// 合法音节集合（字与词音节并集）。
    syllables: HashSet<String>,
    /// 反查：字 → 首选读音（TSV 每字首选读音行在前，见 generate.rs）。
    char_pinyin: HashMap<char, Arc<str>>,
    /// 反查：词 → 拼音（空格分隔）。
    word_pinyin: HashMap<Arc<str>, String>,
}

impl TablePinyinBackend {
    /// Whether packaged character/word data contains usable entries.
    pub fn has_character_data(&self) -> bool {
        !self.chars.is_empty()
    }
    pub fn has_word_data(&self) -> bool {
        !self.words.is_empty()
    }

    /// 用两份 TSV 构建后端；`name` 供诊断。
    pub fn from_tsv(
        chars_tsv: &str,
        words_tsv: &str,
        name: &'static str,
    ) -> Result<Self, TsvError> {
        let mut backend = TablePinyinBackend {
            name,
            ..TablePinyinBackend::default()
        };

        let mut readings: HashMap<&str, Arc<str>> = HashMap::new();
        for (idx, raw) in chars_tsv.lines().enumerate() {
            let line_no = idx + 1;
            let line = raw.trim_start_matches('\u{feff}').trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let fields: Vec<&str> = line.split('\t').collect();
            if fields.len() != 3 {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            let syllable = fields[0].trim();
            let ch_field = fields[1].trim();
            let weight_str = fields[2].trim();
            if syllable.is_empty() || ch_field.is_empty() || weight_str.is_empty() {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            if !syllable.bytes().all(|b| b.is_ascii_lowercase()) {
                return Err(TsvError::InvalidSyllable {
                    line: line_no,
                    value: syllable.to_string(),
                });
            }
            let mut chs = ch_field.chars();
            let ch = match (chs.next(), chs.next()) {
                (Some(c), None) => c,
                _ => {
                    return Err(TsvError::InvalidSyllable {
                        line: line_no,
                        value: ch_field.to_string(),
                    })
                }
            };
            let weight = weight_str
                .parse::<i32>()
                .map_err(|_| TsvError::InvalidWeight {
                    line: line_no,
                    value: weight_str.to_string(),
                })?;

            backend
                .chars
                .entry(syllable.to_string())
                .or_default()
                .push((ch, weight));
            backend.syllables.insert(syllable.to_string());
            backend.char_pinyin.entry(ch).or_insert_with(|| {
                readings
                    .entry(syllable)
                    .or_insert_with(|| Arc::from(syllable))
                    .clone()
            });
        }

        for (idx, raw) in words_tsv.lines().enumerate() {
            let line_no = idx + 1;
            let line = raw.trim_start_matches('\u{feff}').trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let fields: Vec<&str> = line.split('\t').collect();
            if fields.len() != 3 {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            let pinyin = fields[0].trim();
            let word = fields[1].trim();
            let weight_str = fields[2].trim();
            if pinyin.is_empty() || word.is_empty() || weight_str.is_empty() {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            let syllables: Vec<&str> = pinyin.split(' ').filter(|s| !s.is_empty()).collect();
            if syllables.is_empty()
                || syllables
                    .iter()
                    .any(|s| !s.bytes().all(|b| b.is_ascii_lowercase()))
            {
                return Err(TsvError::InvalidSyllable {
                    line: line_no,
                    value: pinyin.to_string(),
                });
            }
            let weight = weight_str
                .parse::<i32>()
                .map_err(|_| TsvError::InvalidWeight {
                    line: line_no,
                    value: weight_str.to_string(),
                })?;

            let pinyin_joined = syllables.join(" ");
            let word: Arc<str> = Arc::from(word);
            backend
                .words
                .entry(pinyin_joined.clone())
                .or_default()
                .push((word.clone(), weight));
            backend
                .initials
                .entry(initials_of(&syllables))
                .or_default()
                .push((word.clone(), weight));
            for s in syllables {
                backend.syllables.insert(s.to_string());
            }
            backend
                .word_pinyin
                .entry(word)
                .or_insert_with(|| pinyin_joined.clone());
        }

        backend.finalize();
        Ok(backend)
    }

    fn finalize(&mut self) {
        for list in self.chars.values_mut() {
            list.shrink_to_fit();
            list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        }
        for list in self.words.values_mut() {
            list.shrink_to_fit();
            list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        }
        for list in self.initials.values_mut() {
            list.shrink_to_fit();
            list.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
        }
    }

    /// 合法音节数（诊断用）。
    pub fn syllable_count(&self) -> usize {
        self.syllables.len()
    }

    /// 字条目数（诊断用）。
    pub fn char_count(&self) -> usize {
        self.chars.values().map(Vec::len).sum()
    }

    /// 词条目数（诊断用）。
    pub fn word_count(&self) -> usize {
        self.words.values().map(Vec::len).sum()
    }
}

/// 由空格分隔音节列表计算首字母串（简拼键）。
fn initials_of(syllables: &[&str]) -> String {
    syllables.iter().filter_map(|s| s.chars().next()).collect()
}

impl PinyinBackend for TablePinyinBackend {
    fn name(&self) -> &'static str {
        self.name
    }

    fn segment(&self, input: &str) -> Vec<String> {
        segment(input, &self.syllables)
    }

    fn convert(&self, input: &str, max: usize) -> Vec<PinyinCandidate> {
        if input.is_empty() || !input.bytes().all(|b| b.is_ascii_lowercase() || b == b'\'') {
            return Vec::new();
        }
        let mut out: Vec<PinyinCandidate> = Vec::new();

        // 1) 全拼：先整词，再单音节字。
        let syllables = self.segment(input);
        if !syllables.is_empty() {
            let key = syllables.join(" ");
            if let Some(words) = self.words.get(&key) {
                for (word, weight) in words {
                    out.push(PinyinCandidate::new(
                        word.to_string(),
                        key.clone(),
                        *weight,
                        false,
                    ));
                }
            }
            if syllables.len() == 1 {
                if let Some(chars) = self.chars.get(&syllables[0]) {
                    for (ch, weight) in chars {
                        out.push(PinyinCandidate::new(
                            ch.to_string(),
                            syllables[0].clone(),
                            *weight,
                            false,
                        ));
                    }
                }
            }
        }

        // 2) 简拼：首字母串匹配词。
        if let Some(words) = self.initials.get(input) {
            for (word, weight) in words {
                out.push(PinyinCandidate::new(
                    word.to_string(),
                    input.to_string(),
                    *weight,
                    true,
                ));
            }
        }

        // 去重（同 text 保留权重高者，全拼优先于简拼），再按权重降序截断。
        out.sort_by(|a, b| {
            b.weight
                .cmp(&a.weight)
                .then(a.is_initial.cmp(&b.is_initial))
                .then(a.text.cmp(&b.text))
        });
        let mut seen = HashSet::new();
        out.retain(|c| seen.insert(c.text.clone()));
        out.truncate(max);
        out
    }

    fn reverse_lookup(&self, text: &str) -> Option<String> {
        let mut chars = text.chars();
        let first = chars.next()?;
        if chars.next().is_none() {
            self.char_pinyin
                .get(&first)
                .map(|pinyin| pinyin.to_string())
        } else {
            self.word_pinyin.get(text).cloned()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 迷你样本表（与 `data/generated/pinyin-*.tsv` 同构）。
    fn sample() -> TablePinyinBackend {
        let chars = "# 音节\t字\tweight\n\
                     wo\t我\t100\n\
                     ni\t你\t90\n\
                     hao\t好\t80\n\
                     zhong\t中\t70\n\
                     wen\t文\t60\n\
                     guo\t国\t50\n\
                     ren\t人\t40\n";
        let words = "# 拼音\t词\tweight\n\
                     ni hao\t你好\t200\n\
                     shi jie\t世界\t180\n\
                     zhong wen\t中文\t160\n\
                     ren min\t人民\t150\n\
                     wo men\t我们\t140\n\
                     zhong guo\t中国\t130\n";
        TablePinyinBackend::from_tsv(chars, words, "test").unwrap()
    }

    #[test]
    fn from_tsv_rejects_bad_lines() {
        assert!(matches!(
            TablePinyinBackend::from_tsv("wo\t我\n", "", "t"),
            Err(TsvError::MissingColumn { line: 1 })
        ));
        assert!(matches!(
            TablePinyinBackend::from_tsv("wo\t我\t很多\n", "", "t"),
            Err(TsvError::InvalidWeight { line: 1, .. })
        ));
        assert!(matches!(
            TablePinyinBackend::from_tsv("Wǒ\t我\t1\n", "", "t"),
            Err(TsvError::InvalidSyllable { line: 1, .. })
        ));
        assert!(matches!(
            TablePinyinBackend::from_tsv("", "ni hao\t你好\t很多\n", "t"),
            Err(TsvError::InvalidWeight { line: 1, .. })
        ));
    }

    #[test]
    fn explicit_syllable_boundaries_do_not_merge_or_accept_empty_parts() {
        let b = TablePinyinBackend::from_tsv(
            "xi\t西\t10\nan\t安\t10\nxian\t先\t20\n",
            "xi an\t西安\t30\n",
            "boundary",
        )
        .unwrap();
        assert_eq!(b.segment("xi'an"), vec!["xi", "an"]);
        assert_eq!(b.convert("xi'an", 9)[0].text, "西安");
        assert_eq!(b.convert("xian", 9)[0].text, "先");
        assert_eq!(b.convert("xi'an", 9)[0].pinyin, "xi an");
        for invalid in ["'xian", "xi'", "xi''an", "xi'aq", "xi’an", "xi an", "XI'an"] {
            assert!(b.convert(invalid, 9).is_empty(), "{invalid}");
        }
    }

    #[test]
    fn segment_uses_collected_syllable_set() {
        let b = sample();
        assert_eq!(b.segment("nihao"), vec!["ni", "hao"]);
        assert!(b.segment("xyz").is_empty());
    }

    #[test]
    fn convert_full_pinyin_single_and_word() {
        let b = sample();
        // wo → 我
        let c = b.convert("wo", 9);
        assert_eq!(c.first().unwrap().text, "我");
        assert!(!c.first().unwrap().is_initial);
        // nihao → 你好（整词优先）
        let c = b.convert("nihao", 9);
        assert_eq!(c.first().unwrap().text, "你好");
    }

    #[test]
    fn convert_initial_letters() {
        let b = sample();
        let c = b.convert("nh", 9);
        assert_eq!(c.first().unwrap().text, "你好");
        assert!(c.first().unwrap().is_initial);
    }

    #[test]
    fn convert_non_ascii_yields_empty() {
        let b = sample();
        assert!(b.convert("你", 9).is_empty());
        assert!(b.convert("", 9).is_empty());
        assert!(b.convert("NI", 9).is_empty());
    }

    #[test]
    fn convert_overlong_and_zero_max() {
        let b = sample();
        // 超长非法输入 → 空，不 panic。
        assert!(b.convert(&"z".repeat(100), 9).is_empty());
        // max=0 → 截断为空。
        assert!(b.convert("wo", 0).is_empty());
    }

    #[test]
    fn reverse_index_shares_readings_and_preserves_first_pronunciation() {
        let backend = TablePinyinBackend::from_tsv(
            "zhong\t中\t100\nzhong\t钟\t80\nchong\t中\t70\n",
            "",
            "test",
        )
        .unwrap();
        assert!(Arc::ptr_eq(
            &backend.char_pinyin[&'中'],
            &backend.char_pinyin[&'钟']
        ));
        assert_eq!(backend.reverse_lookup("中").as_deref(), Some("zhong"));
        let words = TablePinyinBackend::from_tsv("", "ni hao\t你好\t100\n", "test").unwrap();
        let full = &words.words["ni hao"][0].0;
        assert!(Arc::ptr_eq(full, &words.initials["nh"][0].0));
        assert!(Arc::ptr_eq(full, words.word_pinyin.keys().next().unwrap()));
        assert_eq!(words.convert("nh", 1)[0].text, "你好");
    }

    #[test]
    fn adversarial_corpus_is_handled_without_panicking() {
        let long_number = "9".repeat(1000);
        let cases: Vec<String> = vec![
            String::new(),
            "\n\n".into(),
            "# only comment\n".into(),
            "\u{feff}ni\t你\t1\n".into(),
            "ni\t你\t1\r\n".into(),
            "ni\t你\n".into(),
            "NI\t你\t1\n".into(),
            "ni\t你你\t1\n".into(),
            format!("ni\t你\t{long_number}\n"),
            "ni\t你\tx\n".into(),
            "ni hao\t你好\t1\n".into(),
            "ni  hao\t你好\t1\n".into(),
            "ni\thao\t1\n".into(),
            "ni\t你\t1\nni hao\t你好\t2\n".into(),
            "a".repeat(100_000),
        ];
        for case in cases {
            // 同一份输入同时充当字表与词表。
            let _ = TablePinyinBackend::from_tsv(&case, &case, "corpus");
        }
    }

    #[test]
    fn reverse_lookup_char_and_word() {
        let b = sample();
        assert_eq!(b.reverse_lookup("我").as_deref(), Some("wo"));
        assert_eq!(b.reverse_lookup("你好").as_deref(), Some("ni hao"));
        assert_eq!(b.reverse_lookup("未知"), None);
    }

    #[test]
    fn reverse_lookup_prefers_first_listed_reading() {
        // 反查约定：每个字的首选读音（D5 首条）行排在前面。
        let chars = "# 音节\t字\tweight\n\
                     xing\t行\t22128\n\
                     hang\t行\t22128\n\
                     heng\t行\t22128\n\
                     de\t的\t318825\n\
                     di\t的\t318825\n\
                     ni\t你\t234587\n";
        let b = TablePinyinBackend::from_tsv(chars, "", "t").unwrap();
        assert_eq!(b.reverse_lookup("你").as_deref(), Some("ni"));
        assert_eq!(b.reverse_lookup("的").as_deref(), Some("de"));
        assert_eq!(b.reverse_lookup("行").as_deref(), Some("xing"));
    }
}
