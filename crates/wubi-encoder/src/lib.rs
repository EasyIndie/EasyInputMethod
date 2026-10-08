//! 五笔86 字根表建模。
//!
//! 本 crate 只提供"字根表 → 字根到键的查询"；**不实现编码逻辑**
//! （键名字 / 成字字根 / 合体字 / 末笔字型识别码属于 T-M1-02/03）。
//!
//! 零外部依赖、零 IO、零网络（见 `AGENTS.md` 铁律 1/2）。

#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::fmt;

/// 笔画类型：横、竖、撇、捺、折。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Stroke {
    Heng,
    Shu,
    Pie,
    Na,
    Zhe,
}

/// 汉字结构：左右、上下、杂合。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum Structure {
    LeftRight,
    UpDown,
    Mixed,
}

/// 字根表相关错误。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EncodeError {
    /// 字根未知。
    UnknownRadical(String),
    /// 键位非法：不是 `a`–`y` 中的单个小写字母。
    UnknownKey(char),
    /// 输入为空，未解析到任何有效条目。
    EmptyInput,
    /// 行格式非法，附带原始行内容。
    ParseError(String),
}

impl fmt::Display for EncodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EncodeError::UnknownRadical(radical) => write!(f, "未知字根：{radical}"),
            EncodeError::UnknownKey(key) => write!(f, "非法键位：{key}（应为 a–y）"),
            EncodeError::EmptyInput => write!(f, "输入为空，未解析到任何字根"),
            EncodeError::ParseError(line) => write!(f, "字根表行格式非法：{line}"),
        }
    }
}

impl std::error::Error for EncodeError {}

/// 五笔86 字根表：把每个字根映射到其所属键位。
///
/// 键位用单个小写字母 `a`–`y` 表示。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct RadicalTable {
    /// 字根 → 键位。
    radicals: BTreeMap<String, char>,
}

impl RadicalTable {
    /// Parse a radical table from a TSV string.
    ///
    /// Each effective line has the form `key\trad1,rad2,...`, where `key` is a
    /// single lowercase `a`–`y` letter. Lines starting with `#` and blank lines
    /// are skipped; any other malformed line yields [`EncodeError::ParseError`].
    pub fn from_tsv(input: &str) -> Result<Self, EncodeError> {
        let mut radicals = BTreeMap::new();

        for raw_line in input.lines() {
            let line = raw_line.trim();
            if line.is_empty() || line.starts_with('#') {
                continue;
            }

            let mut fields = line.split('\t');
            let key_field = fields.next().unwrap_or_default();
            let radical_field = fields
                .next()
                .ok_or_else(|| EncodeError::ParseError(line.to_string()))?;
            if fields.next().is_some() {
                return Err(EncodeError::ParseError(line.to_string()));
            }

            let key = parse_key(key_field, line)?;

            let radicals_part = radical_field.trim();
            if radicals_part.is_empty() {
                return Err(EncodeError::ParseError(line.to_string()));
            }

            for radical in radicals_part.split(',') {
                let radical = radical.trim();
                if radical.is_empty() {
                    return Err(EncodeError::ParseError(line.to_string()));
                }
                radicals.insert(radical.to_string(), key);
            }
        }

        if radicals.is_empty() {
            return Err(EncodeError::EmptyInput);
        }

        Ok(Self { radicals })
    }

    /// Return the key owning `radical`, or `None` if it is not in the table.
    pub fn radical_to_key(&self, radical: &str) -> Option<char> {
        self.radicals.get(radical).copied()
    }
}

/// Parse and validate a key field, reporting the offending whole line on failure.
fn parse_key(field: &str, line: &str) -> Result<char, EncodeError> {
    let field = field.trim();
    let mut chars = field.chars();
    let first = chars.next();
    if chars.next().is_some() {
        // More than one character: not a valid key field.
        return Err(EncodeError::ParseError(line.to_string()));
    }
    match first {
        Some(c) if ('a'..='y').contains(&c) => Ok(c),
        Some(c) => Err(EncodeError::UnknownKey(c)),
        None => Err(EncodeError::ParseError(line.to_string())),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Minimal public-domain Wubi86 radical fixture (5 keys).
    const FIXTURE: &str = "\
# 五笔86 最小字根表（测试夹具）
g\t王,一,五,戋
f\t土,士,二,干,十

t\t禾,竹,丿,彳
y\t言,讠,方,丶,广
n\t已,己,巳,尸,乙,羽
";

    #[test]
    fn loads_fixture_and_looks_up() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        assert_eq!(table.radical_to_key("王"), Some('g'));
        assert_eq!(table.radical_to_key("十"), Some('f'));
        assert_eq!(table.radical_to_key("丿"), Some('t'));
        assert_eq!(table.radical_to_key("讠"), Some('y'));
        assert_eq!(table.radical_to_key("羽"), Some('n'));
    }

    #[test]
    fn unknown_radical_returns_none() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        assert_eq!(table.radical_to_key("龘"), None);
        assert_eq!(table.radical_to_key(""), None);
    }

    #[test]
    fn unknown_key_is_rejected() {
        assert_eq!(
            RadicalTable::from_tsv("z\t口\n"),
            Err(EncodeError::UnknownKey('z'))
        );
        assert_eq!(
            RadicalTable::from_tsv("A\t口\n"),
            Err(EncodeError::UnknownKey('A'))
        );
    }

    #[test]
    fn comments_and_blank_lines_are_skipped() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        // Only the 5 fixture lines contribute entries; comments/blanks add none.
        assert_eq!(table.radical_to_key("#"), None);
        assert_eq!(table.radical_to_key("五"), Some('g'));
    }

    #[test]
    fn empty_or_comment_only_input_is_empty_error() {
        assert_eq!(RadicalTable::from_tsv(""), Err(EncodeError::EmptyInput));
        assert_eq!(
            RadicalTable::from_tsv("# 只有注释\n\n"),
            Err(EncodeError::EmptyInput)
        );
    }

    #[test]
    fn malformed_lines_are_rejected() {
        // Missing tab separator.
        assert!(matches!(
            RadicalTable::from_tsv("g 王\n"),
            Err(EncodeError::ParseError(_))
        ));
        // Key field longer than one character.
        assert!(matches!(
            RadicalTable::from_tsv("gg\t王\n"),
            Err(EncodeError::ParseError(_))
        ));
        // Empty radical list.
        assert!(matches!(
            RadicalTable::from_tsv("g\t\n"),
            Err(EncodeError::ParseError(_))
        ));
        // Empty radical element.
        assert!(matches!(
            RadicalTable::from_tsv("g\t王,,一\n"),
            Err(EncodeError::ParseError(_))
        ));
        // Extra tab-separated field.
        assert!(matches!(
            RadicalTable::from_tsv("g\t王\t一\n"),
            Err(EncodeError::ParseError(_))
        ));
    }
}
