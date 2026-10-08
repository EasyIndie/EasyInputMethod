//! 五笔86 字根表建模与单字编码。
//!
//! 提供"字根表 → 字根到键的查询"，以及键名字（[`encode_key_name`]）
//! 与成字字根（[`encode_chengzi`]）两类单字编码；合体字 / 末笔字型识别码
//! 属于 T-M1-03。
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
    /// 编码成字字根时笔画数不足（至少需要 2 笔），附带实际笔画数。
    TooFewStrokes(usize),
    /// 行格式非法，附带原始行内容。
    ParseError(String),
}

impl fmt::Display for EncodeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EncodeError::UnknownRadical(radical) => write!(f, "未知字根：{radical}"),
            EncodeError::UnknownKey(key) => write!(f, "非法键位：{key}（应为 a–y）"),
            EncodeError::EmptyInput => write!(f, "输入为空，未解析到任何字根"),
            EncodeError::TooFewStrokes(n) => {
                write!(f, "笔画数不足：{n}（成字字根至少需要 2 笔）")
            }
            EncodeError::ParseError(line) => write!(f, "字根表行格式非法：{line}"),
        }
    }
}

impl std::error::Error for EncodeError {}

/// 五笔86 键名代表字：`(键位, 代表字)`，覆盖 `a`–`y` 共 25 键。
const KEY_NAMES: [(char, char); 25] = [
    ('a', '工'),
    ('b', '子'),
    ('c', '又'),
    ('d', '大'),
    ('e', '月'),
    ('f', '土'),
    ('g', '王'),
    ('h', '目'),
    ('i', '水'),
    ('j', '日'),
    ('k', '口'),
    ('l', '田'),
    ('m', '山'),
    ('n', '已'),
    ('o', '火'),
    ('p', '之'),
    ('q', '金'),
    ('r', '白'),
    ('s', '木'),
    ('t', '禾'),
    ('u', '立'),
    ('v', '女'),
    ('w', '人'),
    ('x', '纟'),
    ('y', '言'),
];

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

    /// Return the Wubi86 key-name representative character for `key`.
    ///
    /// `key` must be a single lowercase `a`–`y` letter; anything else yields `None`.
    /// This mapping is fixed by the layout and independent of the loaded table.
    pub fn key_name_char(&self, key: char) -> Option<char> {
        KEY_NAMES
            .iter()
            .find(|(candidate, _)| *candidate == key)
            .map(|(_, name)| *name)
    }

    /// Return `true` if `c` appears as a radical in this table.
    pub fn is_radical_char(&self, c: &str) -> bool {
        self.radicals.contains_key(c)
    }
}

/// Map a stroke type to its key in the Wubi86 stroke zone.
///
/// 横=G、竖=H、撇=T、捺/点=Y、折=N。
pub fn stroke_to_key(s: Stroke) -> char {
    match s {
        Stroke::Heng => 'g',
        Stroke::Shu => 'h',
        Stroke::Pie => 't',
        Stroke::Na => 'y',
        Stroke::Zhe => 'n',
    }
}

/// Encode a Wubi86 key-name character (键名字): the key repeated four times.
pub fn encode_key_name(key: char) -> String {
    std::iter::repeat_n(key, 4).collect()
}

/// Encode a Wubi86 "chengzi" radical (成字字根) as `key + first + second + last`.
///
/// At least two strokes are required; shorter input yields
/// [`EncodeError::TooFewStrokes`]. An unknown radical yields
/// [`EncodeError::UnknownRadical`].
pub fn encode_chengzi(
    radical: &str,
    strokes: &[Stroke],
    table: &RadicalTable,
) -> Result<String, EncodeError> {
    if strokes.len() < 2 {
        return Err(EncodeError::TooFewStrokes(strokes.len()));
    }
    let key = table
        .radical_to_key(radical)
        .ok_or_else(|| EncodeError::UnknownRadical(radical.to_string()))?;

    let first = stroke_to_key(strokes[0]);
    let second = stroke_to_key(strokes[1]);
    let last = stroke_to_key(strokes[strokes.len() - 1]);

    let mut code = String::with_capacity(4);
    code.push(key);
    code.push(first);
    code.push(second);
    code.push(last);
    Ok(code)
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

    #[test]
    fn key_name_char_covers_all_25_keys() {
        let table = RadicalTable::default();
        assert_eq!(table.key_name_char('g'), Some('王'));
        assert_eq!(table.key_name_char('f'), Some('土'));
        assert_eq!(table.key_name_char('d'), Some('大'));
        assert_eq!(table.key_name_char('t'), Some('禾'));
        assert_eq!(table.key_name_char('y'), Some('言'));
        assert_eq!(table.key_name_char('n'), Some('已'));
        assert_eq!(table.key_name_char('x'), Some('纟'));
        // `z` is not a key in Wubi86, and keys are lowercase only.
        assert_eq!(table.key_name_char('z'), None);
        assert_eq!(table.key_name_char('G'), None);
    }

    #[test]
    fn is_radical_char_checks_membership() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        assert!(table.is_radical_char("王"));
        assert!(table.is_radical_char("羽"));
        assert!(!table.is_radical_char("龘"));
        assert!(!table.is_radical_char(""));
    }

    #[test]
    fn stroke_to_key_maps_wubi_stroke_zone() {
        assert_eq!(stroke_to_key(Stroke::Heng), 'g');
        assert_eq!(stroke_to_key(Stroke::Shu), 'h');
        assert_eq!(stroke_to_key(Stroke::Pie), 't');
        assert_eq!(stroke_to_key(Stroke::Na), 'y');
        assert_eq!(stroke_to_key(Stroke::Zhe), 'n');
    }

    #[test]
    fn key_name_encodes_as_four_repeats() {
        assert_eq!(encode_key_name('g'), "gggg");
        assert_eq!(encode_key_name('f'), "ffff");
    }

    #[test]
    fn chengzi_requires_at_least_two_strokes() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        assert_eq!(
            encode_chengzi("一", &[Stroke::Heng], &table),
            Err(EncodeError::TooFewStrokes(1))
        );
        assert_eq!(
            encode_chengzi("一", &[], &table),
            Err(EncodeError::TooFewStrokes(0))
        );
    }

    #[test]
    fn chengzi_uses_key_plus_first_second_last_stroke() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        // 五 (key g): 一丨𠃍一 simplified to [Heng, Shu, Zhe, Heng].
        let strokes = [Stroke::Heng, Stroke::Shu, Stroke::Zhe, Stroke::Heng];
        assert_eq!(
            encode_chengzi("五", &strokes, &table),
            Ok("gghg".to_string())
        );
    }

    #[test]
    fn chengzi_unknown_radical_is_rejected() {
        let table = RadicalTable::from_tsv(FIXTURE).expect("fixture should parse");
        assert_eq!(
            encode_chengzi("龘", &[Stroke::Heng, Stroke::Shu], &table),
            Err(EncodeError::UnknownRadical("龘".to_string()))
        );
    }
}
