//! 码表引擎（五笔）。
//!
//! M0 用排序数组验证逻辑；M1 换 `cedarwood` 双数组 Trie（预测搜索 + 动态增删 + 持久化，ADR-015）。

#![forbid(unsafe_code)]

use ime_core::{Candidate, CandidateSource, ConvertResult, Engine, EngineType};

/// 码表词条。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub text: String,
    pub weight: i32,
}

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

        // 前缀预测在后（code 比 input 长）
        for (code, entry) in self.table.prefix(input, max) {
            if code == input {
                continue; // 已在精确匹配中
            }
            candidates.push(Candidate {
                text: entry.text,
                code,
                weight: entry.weight,
                source: CandidateSource::CodeTable,
                comment: None,
                is_prefix: true,
            });
            if candidates.len() >= max {
                break;
            }
        }

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

    fn table() -> Table {
        let mut t = Table::new();
        t.insert("w", "人", 100);
        t.insert("wq", "你", 100);
        t.insert("wqiy", "你", 99);
        t.insert("kwwl", "中华人民共和国", 100);
        t.finalize();
        t
    }

    #[test]
    fn exact_lookup() {
        let t = table();
        assert_eq!(t.exact("wq").unwrap()[0].text, "你");
        assert!(t.exact("nope").is_none());
    }

    #[test]
    fn prefix_lookup() {
        let t = table();
        let got: Vec<String> = t
            .prefix("w", 10)
            .into_iter()
            .map(|(code, entry)| format!("{code}:{}", entry.text))
            .collect();
        assert!(got.contains(&"w:人".to_string()));
        assert!(got.contains(&"wq:你".to_string()));
        assert!(got.contains(&"wqiy:你".to_string()));
    }

    #[test]
    fn auto_commit_only_on_full_unique() {
        let t = table();
        let engine = CodeTableEngine::new(t, 4);
        assert_eq!(
            engine.convert("kwwl", 9).should_commit.as_deref(),
            Some("中华人民共和国")
        );
        assert_eq!(engine.convert("wq", 9).should_commit, None);
    }

    #[test]
    fn convert_marks_prefix() {
        let t = table();
        let engine = CodeTableEngine::new(t, 4);
        let result = engine.convert("w", 9);
        assert!(result
            .candidates
            .iter()
            .any(|c| c.text == "人" && !c.is_prefix));
        assert!(result
            .candidates
            .iter()
            .any(|c| c.text == "你" && c.is_prefix));
    }
}
