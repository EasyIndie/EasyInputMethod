//! 码表引擎（五笔）。
//!
//! M0 用排序数组验证逻辑；M1 换 `cedarwood` 双数组 Trie（预测搜索 + 动态增删 + 持久化，ADR-015）。

#![forbid(unsafe_code)]

use std::error::Error;
use std::fmt;

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

/// 码表引擎：把 [`Table`] 适配到 [`Engine`] trait。
pub struct CodeTableEngine {
    table: Table,
    max_code_len: usize,
}

impl CodeTableEngine {
    pub fn new(table: Table, max_code_len: usize) -> Self {
        Self {
            table,
            max_code_len,
        }
    }
}

impl Engine for CodeTableEngine {
    fn convert(&self, input: &str, max: usize) -> ConvertResult {
        let mut candidates: Vec<Candidate> = Vec::new();

        // 精确匹配在前
        if let Some(list) = self.table.exact(input) {
            for entry in list {
                candidates.push(Candidate {
                    text: entry.text.clone(),
                    code: input.to_string(),
                    weight: entry.weight,
                    source: CandidateSource::CodeTable,
                    comment: None,
                    is_prefix: false,
                });
            }
        }

        // 前缀预测在后（code 比 input 长）：收集全部前缀候选后按权重降序截断，
        // 避免按 code 字典序截断而丢掉高频候选（如 wq 前缀下的「你」）。
        let mut prefixes: Vec<Candidate> = self
            .table
            .prefix(input, usize::MAX)
            .into_iter()
            .filter(|(code, _)| code != input)
            .map(|(code, entry)| Candidate {
                text: entry.text,
                code,
                weight: entry.weight,
                source: CandidateSource::CodeTable,
                comment: None,
                is_prefix: true,
            })
            .collect();
        prefixes.sort_by(|a, b| b.weight.cmp(&a.weight).then_with(|| a.text.cmp(&b.text)));
        let room = max.saturating_sub(candidates.len());
        candidates.extend(prefixes.into_iter().take(room));

        // 自动上屏：仅当输入为满码长度且精确唯一（"四码唯一自动上屏"的保守实现）。
        let should_commit = if input.len() == self.max_code_len {
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
