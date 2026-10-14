//! 码表引擎（五笔）。
//!
//! 排序数组 + 文本 TSV；精确二分 + 前缀区间扫描。cedarwood/二进制/mmap 为带触发条件的可选优化（ADR-060）。
//!
//! 内存：`code` 与候选文本存在各自的连续字节缓冲里，用偏移索引；候选扁平存储（ADR-082）。
//! 对外仍暴露 owned 的 [`Entry`]（查询时物化），热路径直接用紧凑存储。

#![forbid(unsafe_code)]

pub mod learning;

use std::error::Error;
use std::fmt;
use std::sync::Arc;

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

/// 码表词条（对外拥有的视图；内部为紧凑偏移存储）。
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

/// 一个 code 组：指向 [`Table::codes`] 的区间，以及其候选在 [`Table::entries`] 的下标区间。
#[derive(Debug, Clone, Copy)]
struct Group {
    code_start: u32,
    code_len: u32,
    entry_start: u32,
    entry_end: u32,
}

/// 紧凑候选：指向 [`Table::texts`] 的区间 + 权重。
#[derive(Debug, Clone, Copy)]
struct Packed {
    text_start: u32,
    text_len: u32,
    weight: i32,
}

/// 内存码表：紧凑连续存储 + 按 `code` 字典序排列的组索引。
///
/// 精确查询用二分；前缀预测用区间扫描（同前缀的 code 在排序后连续）。
#[derive(Debug, Clone, Default)]
pub struct Table {
    /// 全部 code 拼接（按 code 字典序）。
    codes: Box<str>,
    /// 全部候选文本拼接。
    texts: Box<str>,
    /// 按 code 升序的组索引。
    groups: Vec<Group>,
    /// 扁平候选（按组连续）。
    entries: Vec<Packed>,
}

impl Table {
    pub fn new() -> Self {
        Self::default()
    }

    /// 追加一条候选（构建期使用；查询前需 [`Table::finalize`]）。
    pub fn insert(&mut self, code: &str, text: &str, weight: i32) {
        let mut rows = self.rows();
        match rows.iter_mut().find(|(c, _)| c == code) {
            Some((_, list)) => list.push(Entry {
                text: text.to_string(),
                weight,
            }),
            None => rows.push((
                code.to_string(),
                vec![Entry {
                    text: text.to_string(),
                    weight,
                }],
            )),
        }
        *self = Self::from_rows(rows);
    }

    /// 从 TSV 文本（`code\ttext\tweight`）构建码表。
    ///
    /// 解析规则（对不可信输入）：
    /// - 空行与 `#` 开头的注释行忽略；
    /// - 每行必须是 3 列且 code/text 非空，否则 [`TsvError::MissingColumn`]；
    /// - weight 必须可解析为 `i32`，否则 [`TsvError::InvalidWeight`]；
    /// - 同码多候选全部保留，构建完成后组内按 `weight` 降序（等权按 text 升序）。
    pub fn from_tsv(input: &str) -> Result<Table, TsvError> {
        let mut rows: Vec<(String, Vec<Entry>)> = Vec::new();
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
            rows.push((
                code.to_string(),
                vec![Entry {
                    text: text.to_string(),
                    weight,
                }],
            ));
        }
        rows.sort_by(|a, b| a.0.cmp(&b.0));
        let mut grouped: Vec<(String, Vec<Entry>)> = Vec::new();
        for (code, list) in rows {
            match grouped.last_mut() {
                Some((last, entries)) if *last == code => entries.extend(list),
                _ => grouped.push((code, list)),
            }
        }
        let mut table = Self::from_rows(grouped);
        table.finalize();
        Ok(table)
    }

    /// 构建完成后调用一次：组内按权重降序，组间按 code 字典序。
    pub fn finalize(&mut self) {
        let mut rows = self.rows();
        for (_, list) in rows.iter_mut() {
            list.sort_by(|a, b| b.weight.cmp(&a.weight).then_with(|| a.text.cmp(&b.text)));
            list.shrink_to_fit();
        }
        rows.sort_by(|a, b| a.0.cmp(&b.0));
        rows.shrink_to_fit();
        *self = Self::from_rows(rows);
    }

    /// 精确查询：返回该码下的候选（按权重降序）。
    pub fn exact(&self, code: &str) -> Option<Vec<Entry>> {
        let i = self.group_index(code)?;
        Some(
            self.group_entries(i)
                .map(|(text, weight)| Entry {
                    text: text.to_string(),
                    weight,
                })
                .collect(),
        )
    }

    /// 前缀预测：返回所有 `code` 以 `prefix` 开头的 `(code, entry)`，最多 `limit` 条。
    pub fn prefix(&self, prefix: &str, limit: usize) -> Vec<(String, Entry)> {
        let mut out = Vec::new();
        let start = self.groups.partition_point(|g| self.code_of(g) < prefix);
        for i in start..self.groups.len() {
            let code = self.code_of_index(i);
            if !code.starts_with(prefix) {
                break;
            }
            for (text, weight) in self.group_entries(i) {
                if out.len() >= limit {
                    return out;
                }
                out.push((
                    code.to_string(),
                    Entry {
                        text: text.to_string(),
                        weight,
                    },
                ));
            }
        }
        out
    }

    pub fn len(&self) -> usize {
        self.groups.len()
    }

    pub fn is_empty(&self) -> bool {
        self.groups.is_empty()
    }

    // ---- 紧凑存储的内部视图（crate 内使用）----

    fn code_of(&self, g: &Group) -> &str {
        let start = g.code_start as usize;
        &self.codes[start..start + g.code_len as usize]
    }

    fn code_of_index(&self, i: usize) -> &str {
        self.code_of(&self.groups[i])
    }

    fn group_entries(&self, i: usize) -> impl Iterator<Item = (&str, i32)> {
        let g = self.groups[i];
        self.entries[g.entry_start as usize..g.entry_end as usize]
            .iter()
            .map(move |p| {
                let start = p.text_start as usize;
                (&self.texts[start..start + p.text_len as usize], p.weight)
            })
    }

    fn group_index(&self, code: &str) -> Option<usize> {
        self.groups
            .binary_search_by(|g| self.code_of(g).cmp(code))
            .ok()
    }

    /// 解码为可变的 `(code, 候选)` 行（仅供构建/自测）。
    fn rows(&self) -> Vec<(String, Vec<Entry>)> {
        (0..self.groups.len())
            .map(|i| {
                let list = self
                    .group_entries(i)
                    .map(|(text, weight)| Entry {
                        text: text.to_string(),
                        weight,
                    })
                    .collect();
                (self.code_of_index(i).to_string(), list)
            })
            .collect()
    }

    /// 把 `(code, 候选)` 行编码为紧凑存储。
    fn from_rows(rows: Vec<(String, Vec<Entry>)>) -> Self {
        let mut codes = String::new();
        let mut texts = String::new();
        let mut groups = Vec::with_capacity(rows.len());
        let mut entries: Vec<Packed> = Vec::new();
        for (code, list) in rows {
            let code_start = codes.len() as u32;
            codes.push_str(&code);
            let code_len = code.len() as u32;
            let entry_start = entries.len() as u32;
            for e in list {
                let text_start = texts.len() as u32;
                let text_len = e.text.len() as u32;
                texts.push_str(&e.text);
                entries.push(Packed {
                    text_start,
                    text_len,
                    weight: e.weight,
                });
            }
            let entry_end = entries.len() as u32;
            groups.push(Group {
                code_start,
                code_len,
                entry_start,
                entry_end,
            });
        }
        entries.shrink_to_fit();
        groups.shrink_to_fit();
        Self {
            codes: codes.into_boxed_str(),
            texts: texts.into_boxed_str(),
            groups,
            entries,
        }
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
    entries: impl Iterator<Item = (&'a str, i32)>,
    max: usize,
) {
    for (text, weight) in entries {
        let rank: Rank<'a> = (
            code == input,
            weight,
            std::cmp::Reverse(text),
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
                .groups
                .partition_point(|g| self.table.code_of(g) < head);
            for i in start..self.table.groups.len() {
                let code = self.table.code_of_index(i);
                if !head.is_empty() && !code.starts_with(head) {
                    break;
                }
                let matches = code.len() >= input.len()
                    && input
                        .bytes()
                        .zip(code.bytes())
                        .all(|(a, b)| a == b'z' || a == b);
                if matches {
                    push_ranked(&mut top, input, code, self.table.group_entries(i), max);
                }
            }
        } else {
            // 同前缀的码在排序后连续：二分定位起点，命中即区间扫描（不再全表）。
            let start = self
                .table
                .groups
                .partition_point(|g| self.table.code_of(g) < input);
            for i in start..self.table.groups.len() {
                let code = self.table.code_of_index(i);
                if !code.starts_with(input) {
                    break;
                }
                push_ranked(&mut top, input, code, self.table.group_entries(i), max);
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
            let rows = table.rows();
            for (code, entries) in &rows {
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
                        .iter()
                        .map(|c| (c.text.clone(), c.weight, c.is_prefix))
                        .collect();
                    let want = reference(&engine.table, input, max, wildcard);
                    assert_eq!(got, want, "input={input} max={max} wildcard={wildcard}");
                }
            }
        }
    }

    #[test]
    fn from_tsv_parses_normal_lines_and_skips_comments_and_blanks() {
        let t = Table::from_tsv("# comment\n\nwqiy\t你\t234587\n\n").unwrap();
        assert_eq!(t.len(), 1);
        let entries = t.exact("wqiy").unwrap();
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].text, "你");
        assert_eq!(entries[0].weight, 234587);
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
                value: "很多".into()
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
    fn exact_returns_weight_sorted_entries() {
        let t = core_table();
        // kwwl 下两条：中华人民共和国(9989) 在前，中集集团(5) 在后。
        let entries = t.exact("kwwl").unwrap();
        assert_eq!(
            entries.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(),
            vec!["中华人民共和国", "中集集团"]
        );
        // gggg 下 王(19704) 在前，龶(1) 在后。
        let entries = t.exact("gggg").unwrap();
        assert_eq!(
            entries.iter().map(|e| e.text.as_str()).collect::<Vec<_>>(),
            vec!["王", "龶"]
        );
        assert!(t.exact("zzzz").is_none());
    }

    #[test]
    fn prefix_returns_matches_in_code_order_with_limit() {
        let t = core_table();
        let all = t.prefix("wq", 100);
        assert_eq!(
            all.iter().map(|(c, _)| c.as_str()).collect::<Vec<_>>(),
            vec!["wqay", "wqiy", "wqje"]
        );
        assert_eq!(t.prefix("wq", 2).len(), 2);
        assert!(t.prefix("zz", 10).is_empty());
    }
}
