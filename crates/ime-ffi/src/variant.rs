//! 简→繁转换（数据来自 OpenCC STCharacters/STPhrases，见数据登记 D11/D12）。
//!
//! 纯逻辑、无 IO/无 unsafe；在 FFI 边界对候选与上屏文本做**最长匹配**转换。
//! 引擎与用户学习仍存简体，转换只影响对外文本。

use std::collections::HashMap;

/// 简→繁映射表：按 key 的字符长度分桶，便于最长匹配。
pub struct VariantMap {
    /// `buckets[i]` 存放长度为 `i+1` 的 key。
    buckets: Vec<HashMap<String, String>>,
    max_len: usize,
}

impl VariantMap {
    /// 解析 `simplified\ttraditional` TSV（忽略空行与 `#` 注释）。
    pub fn from_tsv(text: &str) -> Self {
        let mut entries: HashMap<String, String> = HashMap::new();
        let mut max_len = 0usize;
        for raw in text.lines() {
            let line = raw.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let Some((key, value)) = line.split_once('\t') else {
                continue;
            };
            let (key, value) = (key.trim(), value.trim());
            if key.is_empty() || value.is_empty() || key == value {
                continue;
            }
            max_len = max_len.max(key.chars().count());
            entries.insert(key.to_string(), value.to_string());
        }
        let mut buckets: Vec<HashMap<String, String>> =
            (0..max_len).map(|_| HashMap::new()).collect();
        for (key, value) in entries {
            let len = key.chars().count();
            buckets[len - 1].insert(key, value);
        }
        Self { buckets, max_len }
    }

    /// 最长匹配转换：从左到右，优先命中更长的 key（词组优先于单字）。
    pub fn to(&self, text: &str) -> String {
        if self.max_len == 0 {
            return text.to_string();
        }
        let chars: Vec<char> = text.chars().collect();
        let mut out = String::with_capacity(text.len() * 3);
        let mut i = 0;
        while i < chars.len() {
            let mut matched = false;
            let max = self.max_len.min(chars.len() - i);
            for len in (1..=max).rev() {
                // `String` key 构造有分配，但候选/上屏串很短，可接受。
                let key: String = chars[i..i + len].iter().collect();
                if let Some(value) = self.buckets[len - 1].get(&key) {
                    out.push_str(value);
                    i += len;
                    matched = true;
                    break;
                }
            }
            if !matched {
                out.push(chars[i]);
                i += 1;
            }
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn longest_match_prefers_phrases_then_chars() {
        let map = VariantMap::from_tsv("# header\n发\t發\n头发\t頭髮\n后\t後\n");
        // 词组优先：头发 → 頭髮（而不是 頭發）。
        assert_eq!(map.to("头发"), "頭髮");
        // 单字兜底。
        assert_eq!(map.to("发"), "發");
        // 混合串：词组 + 单字。
        assert_eq!(map.to("我头发"), "我頭髮");
        // 未收录字符保留。
        assert_eq!(map.to("Abc"), "Abc");
        // 无词组规则时逐字转：皇后 → 皇後。
        assert_eq!(map.to("皇后"), "皇後");
    }

    #[test]
    fn empty_map_is_identity() {
        let map = VariantMap::from_tsv("");
        assert_eq!(map.to("头发"), "头发");
    }
}
