//! 音节处理：去声调、音节集合、连续拼音切分。

use std::collections::HashMap;
use std::collections::HashSet;

/// 单个音节最多 6 个字母（zhuang / shuang / chuang）。
pub const MAX_SYLLABLE_LEN: usize = 6;

/// 把带声调/附加符的拼音字符映射为纯 ASCII 小写；无法识别返回 `None`。
///
/// 覆盖 `pinyin-data`（D5）中出现的全部非 ASCII 字符：
/// - 元音声调：āáǎà / ēéěè / īíǐì / ōóǒò / ūúǔù；
/// - ü 系列（含声调）统一映射为 `v`（拼音输入惯例）；
/// - 成音节鼻/边音：ń/ň/ǹ → n、ḿ → m；ê/ế/ề → e；
/// - 组合附加符 U+0300/U+0304/U+030C 由 [`strip_tones`] 跳过。
pub fn tone_base(c: char) -> Option<char> {
    Some(match c {
        'ā' | 'á' | 'ǎ' | 'à' => 'a',
        'ē' | 'é' | 'ě' | 'è' | 'ê' | 'ế' | 'ề' => 'e',
        'ī' | 'í' | 'ǐ' | 'ì' => 'i',
        'ō' | 'ó' | 'ǒ' | 'ò' => 'o',
        'ū' | 'ú' | 'ǔ' | 'ù' => 'u',
        'ü' | 'ǖ' | 'ǘ' | 'ǚ' | 'ǜ' => 'v',
        'ń' | 'ň' | 'ǹ' => 'n',
        'ḿ' => 'm',
        c if c.is_ascii_lowercase() => c,
        _ => return None,
    })
}

/// 去掉声调与组合附加符，返回纯 ASCII 小写；含无法识别字符时返回 `None`。
pub fn strip_tones(s: &str) -> Option<String> {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\u{0300}' | '\u{0304}' | '\u{030c}' => {} // 组合附加符：跳过
            _ => out.push(tone_base(c)?),
        }
    }
    Some(out)
}

/// 把连续 ASCII 拼音切成合法音节序列（最长优先 + 回溯）；无法完全切分返回空 `Vec`。
pub fn segment(input: &str, syllables: &HashSet<String>) -> Vec<String> {
    if input.is_empty() || !input.is_ascii() {
        return Vec::new();
    }
    fn dfs(
        input: &str,
        pos: usize,
        syllables: &HashSet<String>,
        memo: &mut HashMap<usize, Option<Vec<String>>>,
    ) -> Option<Vec<String>> {
        if pos == input.len() {
            return Some(Vec::new());
        }
        if let Some(hit) = memo.get(&pos) {
            return hit.clone();
        }
        let max_len = MAX_SYLLABLE_LEN.min(input.len() - pos);
        for len in (1..=max_len).rev() {
            // `input` 已校验为 ASCII，按字节切片安全。
            let head = &input[pos..pos + len];
            if syllables.contains(head) {
                if let Some(mut tail) = dfs(input, pos + len, syllables, memo) {
                    let mut result = Vec::with_capacity(1 + tail.len());
                    result.push(head.to_string());
                    result.append(&mut tail);
                    memo.insert(pos, Some(result.clone()));
                    return Some(result);
                }
            }
        }
        memo.insert(pos, None);
        None
    }
    dfs(input, 0, syllables, &mut HashMap::new()).unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tone_base_maps_vowels_ue_and_syllabic_nasals() {
        for (toned, plain) in [
            ('ā', 'a'),
            ('á', 'a'),
            ('ǎ', 'a'),
            ('à', 'a'),
            ('é', 'e'),
            ('ǐ', 'i'),
            ('ǒ', 'o'),
            ('ù', 'u'),
            ('ü', 'v'),
            ('ǘ', 'v'),
            ('ǚ', 'v'),
            ('ǜ', 'v'),
            ('ń', 'n'),
            ('ň', 'n'),
            ('ǹ', 'n'),
            ('ḿ', 'm'),
            ('ê', 'e'),
            ('ế', 'e'),
            ('ề', 'e'),
            ('g', 'g'),
        ] {
            assert_eq!(tone_base(toned), Some(plain), "{toned}");
        }
        assert_eq!(tone_base('你'), None);
        assert_eq!(tone_base('A'), None);
    }

    #[test]
    fn strip_tones_handles_combining_marks() {
        assert_eq!(strip_tones("nǐ").as_deref(), Some("ni"));
        assert_eq!(strip_tones("hǎo").as_deref(), Some("hao"));
        // ê + 组合声调（U+0304）→ e；m + U+0304 → m。
        assert_eq!(strip_tones("ê\u{0304}").as_deref(), Some("e"));
        assert_eq!(strip_tones("m\u{0304}").as_deref(), Some("m"));
        assert_eq!(strip_tones("lǜ").as_deref(), Some("lv"));
        assert_eq!(strip_tones("lüè").as_deref(), Some("lve"));
        assert_eq!(strip_tones("ńg").as_deref(), Some("ng"));
        // ASCII 小写原样保留；含空格或非拼音字符返回 None。
        assert_eq!(strip_tones("x").as_deref(), Some("x"));
        assert_eq!(strip_tones("nǐ hǎo"), None);
        assert_eq!(strip_tones("你"), None);
    }

    #[test]
    fn segment_longest_match_with_backtracking() {
        let syllables: HashSet<String> = [
            "ni", "hao", "wo", "xian", "xi", "an", "zhong", "wen", "guo", "ng", "n",
        ]
        .iter()
        .map(|s| s.to_string())
        .collect();

        assert_eq!(segment("nihao", &syllables), vec!["ni", "hao"]);
        assert_eq!(segment("wo", &syllables), vec!["wo"]);
        // 最长匹配：xian（先）优先于 xi+an。
        assert_eq!(segment("xian", &syllables), vec!["xian"]);
        assert_eq!(segment("zhongwen", &syllables), vec!["zhong", "wen"]);
        // 完全无法切分 → 空。
        assert!(segment("xqz", &syllables).is_empty());
    }

    #[test]
    fn segment_rejects_non_ascii_and_empty() {
        let syllables: HashSet<String> = ["ni"].iter().map(|s| s.to_string()).collect();
        assert!(segment("", &syllables).is_empty());
        assert!(segment("你", &syllables).is_empty());
    }

    #[test]
    fn segment_handles_overlong_input() {
        let syllables: HashSet<String> = ["ni", "hao"].iter().map(|s| s.to_string()).collect();
        // 超长合法序列：不 panic，切出全部音节。
        let long = "nihao".repeat(10);
        let expected: Vec<String> = ["ni".to_string(), "hao".to_string()]
            .into_iter()
            .cycle()
            .take(20)
            .collect();
        assert_eq!(segment(&long, &syllables), expected);
        // 超长非法序列：不 panic，返回空。
        assert!(segment(&"z".repeat(100), &syllables).is_empty());
    }
}
