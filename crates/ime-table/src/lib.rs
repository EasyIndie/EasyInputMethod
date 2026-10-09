//! 码表引擎（五笔）。
//!
//! 排序数组 + 文本 TSV；精确二分 + 前缀区间扫描。cedarwood/二进制/mmap 为带触发条件的可选优化（ADR-060）。

#![forbid(unsafe_code)]

use std::error::Error;
use std::fmt;
use std::sync::Arc;

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

/// 码表词条。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub text: String,
    pub weight: i32,
}

/// 解析 TSV 码表（`code\ttext\tweight`）时的错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TsvError {
    /// 行缺列（列数不是 3，或 code/text 为空）。
    MissingColumn { line: usize },
    /// weight 不是合法整数。
    InvalidWeight { line: usize, value: String },
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
        }
    }
}

impl Error for TsvError {}

/// 内存码表：按 `code` 字典序排列的数组。
///
/// 精确查询用二分；前缀预测用区间扫描（同前缀的 code 在排序后连续）。
#[derive(Debug, Clone, Default)]
pub struct Table {
    /// `(code, 该码下的候选列表)`，按 `code` 字典序排列。
    entries: Vec<(String, Vec<Entry>)>,
}

impl Table {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn insert(&mut self, code: &str, text: &str, weight: i32) {
        match self.entries.iter_mut().find(|(c, _)| c == code) {
            Some((_, list)) => list.push(Entry {
                text: text.to_string(),
                weight,
            }),
            None => self.entries.push((
                code.to_string(),
                vec![Entry {
                    text: text.to_string(),
                    weight,
                }],
            )),
        }
    }

    /// 从 TSV 文本（`code\ttext\tweight`）构建码表。
    ///
    /// 解析规则（对不可信输入）：
    /// - 空行与 `#` 开头的注释行忽略；
    /// - 每行必须是 3 列且 code/text 非空，否则 [`TsvError::MissingColumn`]；
    /// - weight 必须可解析为 `i32`，否则 [`TsvError::InvalidWeight`]；
    /// - 同码多候选全部保留，构建完成后组内按 `weight` 降序（等权按 text 升序）。
    pub fn from_tsv(input: &str) -> Result<Table, TsvError> {
        let mut table = Table::new();
        for (idx, raw) in input.lines().enumerate() {
            let line_no = idx + 1;
            let line = raw.trim_start_matches('\u{feff}').trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let fields: Vec<&str> = line.split('\t').collect();
            if fields.len() != 3 {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            let code = fields[0].trim();
            let text = fields[1].trim();
            let weight_str = fields[2].trim();
            if code.is_empty() || text.is_empty() {
                return Err(TsvError::MissingColumn { line: line_no });
            }
            let weight = weight_str
                .parse::<i32>()
                .map_err(|_| TsvError::InvalidWeight {
                    line: line_no,
                    value: weight_str.to_string(),
                })?;
            table.insert(code, text, weight);
        }
        table.finalize();
        Ok(table)
    }

    /// 构建完成后调用一次：组内按权重降序，组间按 code 字典序。
    pub fn finalize(&mut self) {
        for (_, list) in self.entries.iter_mut() {
            list.sort_by(|a, b| b.weight.cmp(&a.weight).then_with(|| a.text.cmp(&b.text)));
        }
        self.entries.sort_by(|a, b| a.0.cmp(&b.0));
        for (_, list) in &mut self.entries {
            list.shrink_to_fit();
        }
        self.entries.shrink_to_fit();
    }

    /// 精确查询：返回该码下的候选（按权重降序）。
    pub fn exact(&self, code: &str) -> Option<&[Entry]> {
        self.entries
            .binary_search_by(|(c, _)| c.as_str().cmp(code))
            .ok()
            .map(|i| self.entries[i].1.as_slice())
    }

    /// 前缀预测：返回所有 `code` 以 `prefix` 开头的 `(code, entry)`，最多 `limit` 条。
    pub fn prefix(&self, prefix: &str, limit: usize) -> Vec<(String, Entry)> {
        let mut out = Vec::new();
        let start = self
            .entries
            .partition_point(|(code, _)| code.as_str() < prefix);
        for (code, list) in self.entries.iter().skip(start) {
            if !code.starts_with(prefix) {
                break;
            }
            for entry in list {
                if out.len() >= limit {
                    return out;
                }
                out.push((code.clone(), entry.clone()));
            }
        }
        out
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// 候选排序键：精确命中优先 → 权重降序 → 文本升序 → 码升序。
type Rank<'a> = (
    bool,
    i32,
    std::cmp::Reverse<&'a str>,
    std::cmp::Reverse<&'a str>,
);

/// 把 `code` 下的条目按 [`Rank`] 有界并入 top-k 堆（只保留最好的 `max` 个）。
fn push_ranked<'a>(
    top: &mut std::collections::BinaryHeap<std::cmp::Reverse<Rank<'a>>>,
    input: &str,
    code: &'a str,
    entries: &'a [Entry],
    max: usize,
) {
    for entry in entries {
        let rank: Rank<'a> = (
            code == input,
            entry.weight,
            std::cmp::Reverse(entry.text.as_str()),
            std::cmp::Reverse(code),
        );
        if top.len() < max {
            top.push(std::cmp::Reverse(rank));
        } else if top.peek().is_some_and(|worst| rank > worst.0) {
            top.pop();
            top.push(std::cmp::Reverse(rank));
        }
    }
}

/// 码表引擎：把 [`Table`] 适配到 [`Engine`] trait。
pub struct CodeTableEngine {
    table: Arc<Table>,
    max_code_len: usize,
    auto_commit: bool,
    z_wildcard: bool,
}

impl CodeTableEngine {
    pub fn new(table: Table, max_code_len: usize) -> Self {
        Self::new_shared(Arc::new(table), max_code_len)
    }

    /// Share immutable table data while retaining independent engine options.
    pub fn new_shared(table: Arc<Table>, max_code_len: usize) -> Self {
        Self {
            table,
            max_code_len,
            auto_commit: true,
            z_wildcard: false,
        }
    }
}

impl Engine for CodeTableEngine {
    fn configure(&mut self, options: &ime_core::EngineOptions) {
        self.auto_commit = options.auto_commit;
        self.z_wildcard = options.z_wildcard;
    }
    fn convert(&self, input: &str, max: usize) -> ConvertResult {
        use std::cmp::Reverse;
        use std::collections::BinaryHeap;
        let wildcard = self.z_wildcard && input.contains('z');
        let mut top: BinaryHeap<Reverse<Rank<'_>>> = BinaryHeap::new();
        if wildcard {
            // 首个 'z' 之前的字面前缀即所有匹配码的公共前缀；z 在首位时只能扫全表。
            let head = input.split('z').next().unwrap_or("");
            let start = self
                .table
                .entries
                .partition_point(|(code, _)| code.as_str() < head);
            for (code, entries) in &self.table.entries[start..] {
                if !head.is_empty() && !code.starts_with(head) {
                    break;
                }
                let matches = code.len() >= input.len()
                    && input
                        .bytes()
                        .zip(code.bytes())
                        .all(|(a, b)| a == b'z' || a == b);
                if matches {
                    push_ranked(&mut top, input, code, entries, max);
                }
            }
        } else {
            // 同前缀的码在排序后连续：二分定位起点，命中即区间扫描（不再全表）。
            let start = self
                .table
                .entries
                .partition_point(|(code, _)| code.as_str() < input);
            for (code, entries) in &self.table.entries[start..] {
                if !code.starts_with(input) {
                    break;
                }
                push_ranked(&mut top, input, code, entries, max);
            }
        }
        let mut ranked: Vec<_> = top.into_iter().map(|r| r.0).collect();
        ranked.sort_unstable_by(|a, b| b.cmp(a));
        let candidates = ranked
            .into_iter()
            .map(|(_, weight, Reverse(text), Reverse(code))| {
                let mut c = Candidate::new(text, code, weight, CandidateSource::CodeTable);
                c.is_prefix = code.len() > input.len();
                c
            })
            .collect();

        // 自动上屏：仅当输入为满码长度且精确唯一（"四码唯一自动上屏"的保守实现）。
        let should_commit = if self.auto_commit && !wildcard && input.len() == self.max_code_len {
            match self.table.exact(input) {
                Some(list) if list.len() == 1 => Some(list[0].text.clone()),
                _ => None,
            }
        } else {
            None
        };

        ConvertResult {
            candidates,
            should_commit,
        }
    }

    fn engine_type(&self) -> EngineType {
        EngineType::CodeTable
    }

    fn max_code_length(&self) -> usize {
        self.max_code_len
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn adversarial_corpus_is_handled_without_panicking() {
        let long_number = "9".repeat(1000);
        let cases: Vec<String> = vec![
            String::new(),
            "\n\n".into(),
            "# only comment\n".into(),
            "\u{feff}wq\t你\t1\n".into(),
            "wq\t你\t1\r\n".into(),
            "wq\t你\n".into(),
            "wq\t\t1\n".into(),
            "\t你\t1\n".into(),
            format!("wq\t你\t{long_number}\n"),
            "wq\t你\tx\n".into(),
            "wq\t你\t1\textra\n".into(),
            "wq\t🦄\t1\n".into(),
            "a".repeat(100_000),
        ];
        for case in cases {
            let _ = Table::from_tsv(&case);
        }
    }

    /// 真实样本的迷你核心码表（与 `data/generated/wubi86-core.tsv` 同构）。
    fn core_table() -> Table {
        Table::from_tsv(
            "# code\ttext\tweight\n\
             \n\
             wqay\t低\t15504\n\
             wqiy\t你\t234587\n\
             wqje\t像\t31874\n\
             kwwl\t中华人民共和国\t9989\n\
             kwwl\t中集集团\t5\n\
             gggg\t王\t19704\n\
             gggg\t龶\t1\n",
        )
        .unwrap()
    }

    #[test]
    fn bounded_top_k_preserves_best_candidates_for_prefix_and_wildcard() {
        let mut table = Table::new();
        for i in 0..1000 {
            table.insert("abcd", &format!("词{i:04}"), i);
        }
        table.finalize();
        let mut engine = CodeTableEngine::new(table, 4);
        let expected = ["词0999", "词0998", "词0997"];
        assert_eq!(
            engine
                .convert("ab", 3)
                .candidates
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            expected
        );
        engine.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: true,
            fuzzy: false,
        });
        assert_eq!(
            engine
                .convert("zz", 3)
                .candidates
                .iter()
                .map(|c| c.text.as_str())
                .collect::<Vec<_>>(),
            expected
        );
    }

    #[test]
    fn configured_wildcard_and_auto_commit_change_behavior() {
        let mut t = Table::new();
        t.insert("abcd", "甲", 10);
        t.insert("abce", "乙", 9);
        t.finalize();
        let mut e = CodeTableEngine::new(t, 4);
        e.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: true,
            fuzzy: false,
        });
        assert_eq!(e.convert("abcd", 9).should_commit, None);
        let r = e.convert("abcz", 9);
        assert_eq!(r.candidates.len(), 2);
        assert_eq!(r.should_commit, None);
        e.configure(&ime_core::EngineOptions {
            auto_commit: true,
            z_wildcard: false,
            fuzzy: false,
        });
        assert_eq!(e.convert("abcd", 9).should_commit, Some("甲".into()));
        assert!(e.convert("abcz", 9).candidates.is_empty());
    }

    #[test]
    fn convert_matches_full_scan_reference() {
        // 暴力参考实现（旧的全表扫描语义），用于逐条对照优化后的区间扫描。
        fn reference(
            table: &Table,
            input: &str,
            max: usize,
            wildcard: bool,
        ) -> Vec<(String, i32, bool)> {
            use std::cmp::Reverse;
            let mut items: Vec<(bool, i32, Reverse<&str>, Reverse<&str>)> = Vec::new();
            for (code, entries) in &table.entries {
                let matches = if wildcard && input.contains('z') {
                    code.len() >= input.len()
                        && input
                            .bytes()
                            .zip(code.bytes())
                            .all(|(a, b)| a == b'z' || a == b)
                } else {
                    code.starts_with(input)
                };
                if !matches {
                    continue;
                }
                for e in entries {
                    items.push((
                        code == input,
                        e.weight,
                        Reverse(e.text.as_str()),
                        Reverse(code.as_str()),
                    ));
                }
            }
            items.sort_unstable_by(|a, b| b.cmp(a));
            items
                .into_iter()
                .take(max)
                .map(|(_, weight, Reverse(text), Reverse(code))| {
                    (text.to_string(), weight, code.len() > input.len())
                })
                .collect()
        }

        let mut table = Table::new();
        let alphabet = ["a", "b", "z"];
        let mut n = 0;
        for c0 in alphabet {
            for c1 in alphabet {
                for c2 in alphabet {
                    for _ in 0..3 {
                        table.insert(&format!("{c0}{c1}{c2}"), &format!("词{n:03}"), (n * 7) % 50);
                        n += 1;
                    }
                }
            }
        }
        table.finalize();
        let mut engine = CodeTableEngine::new(table, 3);
        for wildcard in [false, true] {
            engine.configure(&ime_core::EngineOptions {
                auto_commit: false,
                z_wildcard: wildcard,
                fuzzy: false,
            });
            for input in [
                "a", "ab", "az", "za", "zz", "azb", "zbz", "aaa", "bbb", "zzz",
            ] {
                for max in [0usize, 1, 3, 9] {
                    let got: Vec<(String, i32, bool)> = engine
                        .convert(input, max)
                        .candidates
                        .into_iter()
                        .map(|c| (c.text, c.weight, c.is_prefix))
                        .collect();
                    assert_eq!(
                        got,
                        reference(&engine.table, input, max, wildcard),
                        "input={input} max={max} wildcard={wildcard}"
                    );
                }
            }
        }
    }

    #[test]
    fn wildcard_head_range_preserves_matching() {
        fn texts(engine: &CodeTableEngine, input: &str) -> Vec<String> {
            engine
                .convert(input, 9)
                .candidates
                .into_iter()
                .map(|c| c.text)
                .collect()
        }
        let mut t = Table::new();
        t.insert("aacd", "甲", 10);
        t.insert("abcd", "乙", 9);
        t.insert("zbcd", "丙", 8);
        t.insert("bbcd", "丁", 7);
        t.finalize();
        let mut e = CodeTableEngine::new(t, 4);
        e.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: true,
            fuzzy: false,
        });
        // 'z' 在第 2 位：字面前缀为 "a"，只应在 a* 区间内匹配。
        assert_eq!(texts(&e, "azcd"), ["甲", "乙"]);
        // 'z' 在首位：退化为整表，按模式匹配；码恰好等于输入者（zbcd）仍优先。
        assert_eq!(texts(&e, "zbcd"), ["丙", "乙", "丁"]);
        // 未开启通配：按字面前缀处理，无匹配。
        e.configure(&ime_core::EngineOptions {
            auto_commit: false,
            z_wildcard: false,
            fuzzy: false,
        });
        assert!(texts(&e, "azcd").is_empty());
    }

    #[test]
    fn from_tsv_parses_normal_lines_and_skips_comments_and_blanks() {
        let t = Table::from_tsv("# comment\n\nwqiy\t你\t234587\n\n").unwrap();
        assert_eq!(t.len(), 1);
        assert_eq!(t.exact("wqiy").unwrap()[0].text, "你");
    }

    #[test]
    fn from_tsv_rejects_missing_column() {
        let err = Table::from_tsv("wqiy\t你\n").unwrap_err();
        assert_eq!(err, TsvError::MissingColumn { line: 1 });
    }

    #[test]
    fn from_tsv_rejects_invalid_weight() {
        let err = Table::from_tsv("wqiy\t你\t很多\n").unwrap_err();
        assert_eq!(
            err,
            TsvError::InvalidWeight {
                line: 1,
                value: "很多".to_string()
            }
        );
    }

    #[test]
    fn from_tsv_rejects_empty_code_or_text() {
        assert_eq!(
            Table::from_tsv("\t你\t1\n").unwrap_err(),
            TsvError::MissingColumn { line: 1 }
        );
        assert_eq!(
            Table::from_tsv("wqiy\t\t1\n").unwrap_err(),
            TsvError::MissingColumn { line: 1 }
        );
    }

    #[test]
    fn exact_lookup_orders_duplicates_by_weight() {
        let t = core_table();
        assert_eq!(t.exact("kwwl").unwrap()[0].text, "中华人民共和国");
        let gggg: Vec<&str> = t
            .exact("gggg")
            .unwrap()
            .iter()
            .map(|e| e.text.as_str())
            .collect();
        assert_eq!(gggg, ["王", "龶"]);
        assert!(t.exact("nope").is_none());
    }

    #[test]
    fn convert_wq_puts_ni_first() {
        let t = core_table();
        let engine = CodeTableEngine::new(t, 4);
        let result = engine.convert("wq", 9);
        assert_eq!(result.candidates.first().unwrap().text, "你");
        assert!(result.candidates.first().unwrap().is_prefix);
    }

    #[test]
    fn convert_prefix_truncates_by_weight_not_code_order() {
        let t = core_table();
        let engine = CodeTableEngine::new(t, 4);
        // 「低」的 code（wqay）字典序在「你」之前，但权重更低，不应被优先截断进来。
        let result = engine.convert("wq", 2);
        let texts: Vec<&str> = result.candidates.iter().map(|c| c.text.as_str()).collect();
        assert_eq!(texts, ["你", "像"]);
    }

    #[test]
    fn auto_commit_only_on_full_unique() {
        let t = core_table();
        let engine = CodeTableEngine::new(t, 4);
        // wqiy 满码且唯一（样本里仅一个 wqiy 候选）。
        assert_eq!(
            engine.convert("wqiy", 9).should_commit.as_deref(),
            Some("你")
        );
        // kwwl 满码但多候选，不自动上屏。
        assert_eq!(engine.convert("kwwl", 9).should_commit, None);
        assert_eq!(engine.convert("wq", 9).should_commit, None);
    }

    #[test]
    fn convert_marks_prefix() {
        let t = core_table();
        let engine = CodeTableEngine::new(t, 4);
        let result = engine.convert("wq", 9);
        assert!(result
            .candidates
            .iter()
            .any(|c| c.text == "你" && c.is_prefix));
        assert!(result
            .candidates
            .iter()
            .any(|c| c.text == "像" && c.is_prefix));
    }
}
