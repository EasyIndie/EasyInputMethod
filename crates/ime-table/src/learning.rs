//! Read-only Wubi86 teaching facts, independent of input mode and candidate ranking.

const CODES: &[u8] = include_bytes!("../../../data/generated/wubi86-learning-codes.bin");
const ROOTS: &str = include_str!("../../../data/learning/wubi86-roots.tsv");

/// A verified readable root and its keyboard code.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RootKey {
    pub root: &'static str,
    pub key: &'static str,
}

/// An independently verified teaching record; absent records must not be inferred.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decomposition {
    pub category: &'static str,
    pub rule: &'static str,
    pub roots: Vec<RootKey>,
    pub recognition: Option<RootKey>,
}

/// One character's complete code and optional verified decomposition.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CharacterLearning {
    pub character: char,
    pub full_code: Option<&'static str>,
    pub decomposition: Option<Decomposition>,
}

/// Bounded candidate teaching data. Missing code and missing explanation are distinct.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Learning {
    pub full_code: Option<String>,
    pub rule: &'static str,
    pub characters: Vec<CharacterLearning>,
}

/// Return a full primary code by scalar binary search, without allocation or IO.
pub fn full_code(character: char) -> Option<&'static str> {
    let mut low = 0;
    let mut high = CODES.len() / 8;
    while low < high {
        let middle = low + (high - low) / 2;
        let row = &CODES[middle * 8..middle * 8 + 8];
        let scalar = u32::from_le_bytes([row[0], row[1], row[2], row[3]]);
        match scalar.cmp(&(character as u32)) {
            std::cmp::Ordering::Less => low = middle + 1,
            std::cmp::Ordering::Greater => high = middle,
            std::cmp::Ordering::Equal => {
                let end = row[4..].iter().position(|b| *b == 0).unwrap_or(4);
                return std::str::from_utf8(&row[4..4 + end]).ok();
            }
        }
    }
    None
}

fn root_key(value: &'static str) -> Option<RootKey> {
    let (root, key) = value.rsplit_once(':')?;
    Some(RootKey { root, key })
}

fn decomposition(character: char) -> Option<Decomposition> {
    static INDEX: std::sync::OnceLock<Vec<&'static str>> = std::sync::OnceLock::new();
    let rows = INDEX.get_or_init(|| {
        ROOTS
            .lines()
            .filter(|line| !line.is_empty() && !line.starts_with('#'))
            .collect()
    });
    let index = rows
        .binary_search_by_key(&(character as u32), |line| {
            line.chars().next().map_or(0, |c| c as u32)
        })
        .ok()?;
    let mut fields = rows[index].split('\t');
    let _character = fields.next()?;
    let _code = fields.next()?;
    let category = fields.next()?;
    let rule = fields.next()?;
    let roots = fields
        .next()?
        .split_whitespace()
        .filter_map(root_key)
        .collect();
    let recognition = root_key(fields.next()?);
    Some(Decomposition {
        category,
        rule,
        roots,
        recognition,
    })
}

/// Query at most 32 characters / 128 UTF-8 bytes. It never learns or changes a session.
pub fn query(text: &str) -> Option<Learning> {
    if text.is_empty() || text.len() > 128 || text.chars().any(char::is_control) {
        return None;
    }
    let characters: Vec<_> = text
        .chars()
        .map(|character| CharacterLearning {
            character,
            full_code: full_code(character),
            decomposition: decomposition(character),
        })
        .collect();
    if characters.len() > 32 {
        return None;
    }
    let rule = match characters.len() {
        1 => characters[0]
            .decomposition
            .as_ref()
            .map_or("拆字说明暂缺", |d| d.rule),
        2 => "两字各取前两码",
        3 => "前两字各取首码，第三字取前两码",
        _ => "前三字与末字各取首码",
    };
    let codes: Option<Vec<_>> = characters.iter().map(|c| c.full_code).collect();
    let full_code = codes.and_then(|codes| {
        let pieces: Option<Vec<&str>> = match codes.len() {
            1 => Some(vec![codes[0]]),
            2 => codes.iter().map(|code| code.get(..2)).collect(),
            3 => Some(vec![
                codes[0].get(..1)?,
                codes[1].get(..1)?,
                codes[2].get(..2)?,
            ]),
            _ => Some(vec![
                codes[0].get(..1)?,
                codes[1].get(..1)?,
                codes[2].get(..1)?,
                codes.last()?.get(..1)?,
            ]),
        };
        Some(pieces?.concat())
    });
    Some(Learning {
        full_code,
        rule,
        characters,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn primary_index_is_sorted_complete_and_queryable() {
        assert_eq!(CODES.len() % 8, 0);
        assert_eq!(CODES.len() / 8, 27_823);
        let mut previous = 0;
        for row in CODES.as_chunks::<8>().0 {
            let scalar = u32::from_le_bytes([row[0], row[1], row[2], row[3]]);
            assert!(scalar > previous);
            previous = scalar;
            let code = full_code(char::from_u32(scalar).unwrap()).unwrap();
            assert!((1..=4).contains(&code.len()));
            assert!(code.bytes().all(|b| (b'a'..=b'y').contains(&b)));
        }
    }

    #[test]
    fn embedded_codes_match_every_primary_entry() {
        for line in include_str!("../../../data/generated/wubi86-single.tsv").lines() {
            if line.is_empty() || line.starts_with('#') {
                continue;
            }
            let fields: Vec<_> = line.split('\t').collect();
            assert_eq!(
                full_code(fields[1].chars().next().unwrap()),
                Some(fields[0])
            );
        }
    }

    #[test]
    fn roots_and_recognition_are_distinct_and_reconstruct_code() {
        for text in ["你", "好", "中", "华", "共", "和", "国"] {
            let item = query(text).unwrap();
            let d = item.characters[0].decomposition.as_ref().unwrap();
            let actual: String = d
                .roots
                .iter()
                .map(|r| r.key)
                .chain(d.recognition.iter().map(|r| r.key))
                .collect();
            assert_eq!(Some(actual), item.full_code);
            assert!(d.recognition.is_some());
        }
        let person = query("人").unwrap();
        assert_eq!(person.full_code.as_deref(), Some("wwww"));
        let d = person.characters[0].decomposition.as_ref().unwrap();
        assert_eq!(d.category, "key_name");
        assert!(d.recognition.is_none());
    }

    #[test]
    fn phrases_use_full_codes_and_preserve_every_character() {
        assert_eq!(query("你好").unwrap().full_code.as_deref(), Some("wqvb"));
        assert_eq!(query("中国人").unwrap().full_code.as_deref(), Some("klww"));
        let item = query("中华人民共和国").unwrap();
        assert_eq!(item.full_code.as_deref(), Some("kwwl"));
        assert_eq!(item.characters.len(), 7);
        assert_eq!(
            item.characters
                .iter()
                .map(|c| c.character)
                .collect::<String>(),
            "中华人民共和国"
        );
        let people = &item.characters[3];
        assert_eq!(people.full_code, Some("nav"));
        assert_eq!(
            people
                .decomposition
                .as_ref()
                .unwrap()
                .recognition
                .as_ref()
                .unwrap()
                .key,
            "v"
        );
    }

    #[test]
    fn generated_teaching_types_preserve_uncertainty_and_publication_boundaries() {
        let mut previous = 0;
        for row in ROOTS
            .lines()
            .filter(|line| !line.starts_with('#') && !line.is_empty())
        {
            let fields: Vec<_> = row.split('\t').collect();
            assert_eq!(fields.len(), 6);
            let character = fields[0].chars().next().unwrap();
            assert!(character as u32 > previous);
            previous = character as u32;
            assert_eq!(full_code(character), Some(fields[1]));
            assert!(!row
                .chars()
                .any(|c| matches!(c as u32, 0xe000..=0xf8ff | 0xf0000..=0x10ffff)));
            let d = decomposition(character).unwrap();
            let keys: String = d.roots.iter().map(|r| r.key).collect();
            match d.category {
                "partial" => {
                    assert_eq!(keys, &fields[1][..fields[1].len() - 1]);
                    assert!(d.recognition.is_none());
                    assert!(d.rule.contains("说明暂缺"));
                }
                "selected_roots" | "chengzi" | "stroke" => {
                    assert_eq!(keys, fields[1]);
                    assert!(d.recognition.is_none());
                }
                "key_name" => assert_eq!(keys.repeat(4), fields[1]),
                "compound" => assert_eq!(keys + d.recognition.as_ref().unwrap().key, fields[1]),
                _ => panic!("unknown teaching category"),
            }
        }
        assert_eq!(
            query("小").unwrap().characters[0]
                .decomposition
                .as_ref()
                .unwrap()
                .category,
            "chengzi"
        );
        assert_eq!(
            query("凡").unwrap().characters[0]
                .decomposition
                .as_ref()
                .unwrap()
                .category,
            "partial"
        );
        assert_eq!(
            query("噤").unwrap().characters[0]
                .decomposition
                .as_ref()
                .unwrap()
                .category,
            "selected_roots"
        );
    }

    #[test]
    fn verified_examples_cover_every_recognition_key_and_basic_strokes() {
        let keys: std::collections::BTreeSet<_> = "好字本叶华中杉少才你共国亿艺电"
            .chars()
            .map(|c| decomposition(c).unwrap().recognition.unwrap().key)
            .collect();
        assert_eq!(keys.len(), 15);
        for (text, code) in [
            ("一", "ggll"),
            ("丨", "hhll"),
            ("丿", "ttll"),
            ("丶", "yyll"),
            ("乙", "nnll"),
        ] {
            let item = query(text).unwrap();
            assert_eq!(item.full_code.as_deref(), Some(code));
            assert_eq!(
                item.characters[0].decomposition.as_ref().unwrap().category,
                "stroke"
            );
        }
        let country = query("中华人民共和国").unwrap();
        assert!(country.characters.iter().all(|c| c.decomposition.is_some()));
    }

    #[test]
    fn missing_data_and_oversized_queries_are_explicit() {
        let missing = query("😀").unwrap();
        assert!(missing.full_code.is_none());
        assert!(missing.characters[0].decomposition.is_none());
        assert!(query("你😀").unwrap().full_code.is_none());
        for input in ["", "你\t好", "你\n好"] {
            assert!(query(input).is_none());
        }
        assert!(query(&"人".repeat(33)).is_none());
        assert!(query(&"a".repeat(129)).is_none());
    }
}
