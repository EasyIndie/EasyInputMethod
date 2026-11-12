//! 双拼（小鹤方案）：把「两键一音节」的输入展开成全拼，再交给全拼后端（ADR-336）。
//!
//! 只做按键 → 音节的确定性映射，不带任何数据；音节是否合法由调用方给的判定函数决定。

/// 小鹤双拼：声母键 → 声母。`u`=sh、`i`=ch、`v`=zh，其余与全拼相同。
fn initial(key: u8) -> Option<&'static str> {
    Some(match key {
        b'b' => "b",
        b'p' => "p",
        b'm' => "m",
        b'f' => "f",
        b'd' => "d",
        b't' => "t",
        b'n' => "n",
        b'l' => "l",
        b'g' => "g",
        b'k' => "k",
        b'h' => "h",
        b'j' => "j",
        b'q' => "q",
        b'x' => "x",
        b'r' => "r",
        b'z' => "z",
        b'c' => "c",
        b's' => "s",
        b'y' => "y",
        b'w' => "w",
        b'u' => "sh",
        b'i' => "ch",
        b'v' => "zh",
        _ => return None,
    })
}

/// 小鹤双拼：韵母键 → 可能的韵母（一键至多两个，按常见程度排）。
fn finals(key: u8) -> &'static [&'static str] {
    match key {
        b'q' => &["iu"],
        b'w' => &["ei"],
        b'e' => &["e"],
        b'r' => &["uan"],
        b't' => &["ue", "ve"],
        b'y' => &["un"],
        b'u' => &["u"],
        b'i' => &["i"],
        b'o' => &["uo", "o"],
        b'p' => &["ie"],
        b'a' => &["a"],
        b's' => &["ong", "iong"],
        b'd' => &["ai"],
        b'f' => &["en"],
        b'g' => &["eng"],
        b'h' => &["ang"],
        b'j' => &["an"],
        b'k' => &["uai", "ing"],
        b'l' => &["iang", "uang"],
        b'z' => &["ou"],
        b'x' => &["ia", "ua"],
        b'c' => &["ao"],
        b'v' => &["ui", "v"],
        b'b' => &["in"],
        b'n' => &["iao"],
        b'm' => &["ian"],
        _ => &[],
    }
}

/// 一对按键 → 一个合法音节；`valid` 判定音节是否存在于数据里。
fn syllable(first: u8, second: u8, valid: &dyn Fn(&str) -> bool) -> Option<String> {
    // 零声母：首键就是韵母的第一个字母。`aa`=a、`ai`=ai、`ah`=ang、`eg`=eng、`ou`=ou…
    if matches!(first, b'a' | b'o' | b'e') {
        let head = first as char;
        let mut options: Vec<String> = Vec::new();
        if first == second {
            options.push(head.to_string());
        }
        options.push(format!("{head}{}", second as char));
        options.extend(
            finals(second)
                .iter()
                .filter(|f| f.starts_with(head))
                .map(|f| (*f).to_string()),
        );
        return options.into_iter().find(|s| valid(s));
    }
    let initial = initial(first)?;
    finals(second)
        .iter()
        .map(|f| format!("{initial}{f}"))
        .find(|s| valid(s))
}

/// 展开结果：全拼串与每个音节的长度（用来把全拼上的字节偏移换算回按键数）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Expanded {
    /// 展开后的全拼（音节直接相连；末尾可能带一个没打完的声母）。
    pub full: String,
    /// 每个完整音节在 `full` 里的字节长度，按顺序。
    pub lengths: Vec<usize>,
}

impl Expanded {
    /// 全拼串上的前 `consumed` 个字节对应多少个按键；不落在音节边界上返回 `None`。
    pub fn keys_for(&self, consumed: usize) -> Option<usize> {
        let mut total = 0;
        for (index, length) in self.lengths.iter().enumerate() {
            total += length;
            if total == consumed {
                return Some((index + 1) * 2);
            }
        }
        None
    }
}

/// 把小鹤双拼输入展开成全拼。任何一对按键拼不出合法音节时返回 `None`（不猜）。
///
/// 奇数个按键时，最后一个键当作没打完的声母接在后面，让后端给出补全。
pub fn expand(input: &str, valid: &dyn Fn(&str) -> bool) -> Option<Expanded> {
    let bytes = input.as_bytes();
    if bytes.is_empty() || !bytes.iter().all(u8::is_ascii_lowercase) {
        return None;
    }
    let mut full = String::new();
    let mut lengths = Vec::with_capacity(bytes.len() / 2);
    for pair in bytes.chunks(2) {
        match pair {
            [first, second] => {
                let s = syllable(*first, *second, valid)?;
                lengths.push(s.len());
                full.push_str(&s);
            }
            [last] => full.push_str(initial(*last).unwrap_or(match last {
                b'a' => "a",
                b'o' => "o",
                _ => "e",
            })),
            _ => return None,
        }
    }
    Some(Expanded { full, lengths })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn valid(s: &str) -> bool {
        [
            "ni", "hao", "shi", "jie", "zhong", "guo", "chuang", "xiang", "lve", "lv", "jue", "an",
            "ang", "a", "e", "eng", "er", "ou", "ai", "kuai", "qing", "xiong", "wo", "luo", "bo",
            "gui", "xia", "hua",
        ]
        .contains(&s)
    }

    /// 小鹤方案打不出的音节：鼻音叹词没有键位；`lo` 与 `luo` 同键，取更常用的 `luo`。全拼模式仍可输入。
    const UNREACHABLE: [&str; 6] = ["hm", "hng", "lo", "m", "n", "ng"];

    fn full(input: &str) -> Option<String> {
        expand(input, &valid).map(|e| e.full)
    }

    #[test]
    fn pairs_expand_to_syllables_and_pick_the_valid_final() {
        assert_eq!(full("nihc").as_deref(), Some("nihao"));
        assert_eq!(full("uijp").as_deref(), Some("shijie"));
        assert_eq!(full("vsgo").as_deref(), Some("zhongguo"));
        // 一键两韵：按音节是否存在取舍。
        assert_eq!(full("il").as_deref(), Some("chuang"));
        assert_eq!(full("xl").as_deref(), Some("xiang"));
        assert_eq!(full("lt").as_deref(), Some("lve"));
        assert_eq!(full("jt").as_deref(), Some("jue"));
        assert_eq!(full("lv").as_deref(), Some("lv"));
        assert_eq!(full("gv").as_deref(), Some("gui"));
        assert_eq!(full("kk").as_deref(), Some("kuai"));
        assert_eq!(full("qk").as_deref(), Some("qing"));
        assert_eq!(full("xs").as_deref(), Some("xiong"));
        assert_eq!(full("lo").as_deref(), Some("luo"));
        assert_eq!(full("bo").as_deref(), Some("bo"));
        assert_eq!(full("xx").as_deref(), Some("xia"));
        assert_eq!(full("hx").as_deref(), Some("hua"));
    }

    #[test]
    fn zero_initial_syllables_use_the_vowel_as_first_key() {
        assert_eq!(full("aa").as_deref(), Some("a"));
        assert_eq!(full("ee").as_deref(), Some("e"));
        assert_eq!(full("an").as_deref(), Some("an"));
        assert_eq!(full("ah").as_deref(), Some("ang"));
        assert_eq!(full("eg").as_deref(), Some("eng"));
        assert_eq!(full("er").as_deref(), Some("er"));
        assert_eq!(full("ou").as_deref(), Some("ou"));
        assert_eq!(full("ai").as_deref(), Some("ai"));
    }

    /// 用随包的真实音节表核对映射：除了全拼里也没有标准双拼键位的几个叹词音节，其余都必须能打出来。
    #[test]
    fn every_packaged_syllable_is_reachable_with_two_keys() {
        let path = concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../data/generated/pinyin-chars.tsv"
        );
        let data = std::fs::read_to_string(path).unwrap();
        let syllables: std::collections::BTreeSet<&str> = data
            .lines()
            .filter(|line| !line.starts_with('#'))
            .filter_map(|line| line.split('\t').next())
            .collect();
        let valid = |s: &str| syllables.contains(s);
        let mut reached = std::collections::BTreeSet::new();
        for first in b'a'..=b'z' {
            for second in b'a'..=b'z' {
                let keys = [first, second];
                let input = std::str::from_utf8(&keys).unwrap();
                if let Some(e) = expand(input, &valid) {
                    reached.insert(e.full);
                }
            }
        }
        let missing: Vec<&str> = syllables
            .iter()
            .copied()
            .filter(|s| !reached.contains(*s))
            .collect();
        assert_eq!(missing, UNREACHABLE, "双拼打不出来的音节");
    }

    #[test]
    fn odd_key_is_an_unfinished_initial_and_bad_pairs_are_not_guessed() {
        let e = expand("nihcu", &valid).unwrap();
        assert_eq!(e.full, "nihaosh");
        assert_eq!(e.lengths, [2, 3]);
        assert_eq!(e.keys_for(2), Some(2));
        assert_eq!(e.keys_for(5), Some(4));
        assert_eq!(e.keys_for(3), None);
        assert_eq!(full("nq"), None); // niu 不在测试音节表里
        assert_eq!(full(""), None);
        assert_eq!(full("ni'h"), None);
        assert_eq!(full("NI"), None);
    }
}
