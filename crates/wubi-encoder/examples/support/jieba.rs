//! jieba `dict.txt`（D10，MIT）解析：通用词表 + 词频。
//!
//! 仅解析前两列（词、频次），忽略词性；纯字符串处理，无 IO / 无网络。
//! 数据源见 `docs/数据来源与许可.md` §1.7 / `data/sources.toml` D10。

use std::collections::HashMap;

/// jieba 词表条目。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    /// 词。
    pub word: String,
    /// 频次（jieba 语料统计）。
    pub freq: u32,
}

/// Parse a jieba `dict.txt` body.
///
/// Each effective line has the form `词 频次 词性` (whitespace separated); the
/// part-of-speech column is ignored. If the same word appears more than once the
/// maximum frequency is kept. Blank lines and `#` comments are skipped; any other
/// malformed line yields an `Err` including its line number.
pub fn parse(input: &str) -> Result<Vec<Entry>, String> {
    let mut entries: Vec<Entry> = Vec::new();
    let mut index: HashMap<String, usize> = HashMap::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split_whitespace();
        let word = fields
            .next()
            .ok_or_else(|| format!("jieba 词表第 {lineno} 行缺少词：{line}"))?;
        let freq_field = fields
            .next()
            .ok_or_else(|| format!("jieba 词表第 {lineno} 行缺少频次：{line}"))?;
        let freq: u32 = freq_field
            .parse()
            .map_err(|e| format!("jieba 词表第 {lineno} 行频次非法：{freq_field}（{e}）"))?;
        match index.get(word) {
            Some(&i) => {
                if freq > entries[i].freq {
                    entries[i].freq = freq;
                }
            }
            None => {
                index.insert(word.to_string(), entries.len());
                entries.push(Entry {
                    word: word.to_string(),
                    freq,
                });
            }
        }
    }
    Ok(entries)
}

/// Return `true` if `c` is a Han ideograph (CJK Unified Ideographs / Extension A).
pub fn is_han(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}')
}
