//! T-M2-02：生成内置轻量拼音兜底的两张表。
//!
//! 输入（均 MIT，见 `data/sources.toml` / `docs/数据来源与许可.md`）：
//!   - D5  `mozillazg/pinyin-data`（字→拼音，带声调）；
//!   - D4  `mozillazg/phrase-pinyin-data`（词→拼音，带声调）；
//!   - D10 `fxsjy/jieba` `dict.txt`（词表 + 词频）。
//!
//! 输出：
//!   - `data/generated/pinyin-chars.tsv`（`音节\t字\tweight`）；
//!   - `data/generated/pinyin-words.tsv`（`拼音(空格分隔)\t词\tweight`）；
//!   - `data/generated/pinyin-report.txt`。
//!
//! 拼音一律去声调、ü→v（拼音输入惯例）。词表主源为 jieba（词频真实，ADR-013），
//! 词拼音由 D5 单字首选读音逐字拼接；再用 D4 的权威词拼音覆盖（修正多音字词，
//! 如「便宜 → pian yi」）。先运行 `./data/sources/fetch-pinyin-data.sh` 下载 D5。
//!
//! 用法（仓库根目录）：
//!   cargo run -p ime-pinyin --example generate
//! 可选位置参数覆盖路径：`... -- <d5> <d4> <jieba> <chars-out> <words-out> <report-out>`。

use std::collections::{BTreeMap, HashMap, HashSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use ime_pinyin::strip_tones;

/// 词频缺省值（排在 jieba 最小频次之后）。
const DEFAULT_WEIGHT: i32 = 1;

/// D5 条目：字 + 无调读音列表。
type D5Entry = (char, Vec<String>);

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let d5_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/pinyin-data.txt"));
    let d4_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/phrase-pinyin-data-pinyin.txt"));
    let jieba_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/jieba-dict.txt"));
    let chars_out = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/pinyin-chars.tsv"));
    let words_out = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/pinyin-words.tsv"));
    let report_out = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/pinyin-report.txt"));

    let d5_text = fs::read_to_string(&d5_path)
        .map_err(|e| format!("读取 D5 失败（{}）：{e}", d5_path.display()))?;
    let d4_text = fs::read_to_string(&d4_path)
        .map_err(|e| format!("读取 D4 失败（{}）：{e}", d4_path.display()))?;
    let jieba_text = fs::read_to_string(&jieba_path)
        .map_err(|e| format!("读取 jieba 失败（{}）：{e}", jieba_path.display()))?;

    let d5 = parse_d5(&d5_text)?;
    let d4 = parse_d4(&d4_text)?;
    let jieba = parse_jieba(&jieba_text)?;

    // 单字首选读音（D5 第一条）。
    let primary: HashMap<char, String> = d5
        .iter()
        .map(|(ch, readings)| (*ch, readings[0].clone()))
        .collect();

    // 单字权重（jieba 单字频次，缺者 1）。
    let char_weight: HashMap<char, i32> = jieba
        .iter()
        .filter(|(w, _)| w.chars().count() == 1)
        .filter_map(|(w, f)| w.chars().next().map(|c| (c, *f as i32)))
        .fold(HashMap::new(), |mut m, (c, f)| {
            let e = m.entry(c).or_insert(0);
            if f > *e {
                *e = f;
            }
            m
        });

    // ---- 字表：音节 → 字 ----
    // 每条记录带 primary 标记：D5 首条读音是首选读音（供 reverse_lookup 返回首选）。
    let mut char_rows: Vec<(String, char, i32, bool)> = Vec::new();
    let mut char_seen: HashSet<(String, char)> = HashSet::new();
    for (ch, readings) in &d5 {
        let weight = char_weight.get(ch).copied().unwrap_or(DEFAULT_WEIGHT);
        for (idx, r) in readings.iter().enumerate() {
            if char_seen.insert((r.clone(), *ch)) {
                char_rows.push((r.clone(), *ch, weight, idx == 0));
            }
        }
    }
    // 按字分组；组内首选读音在前、其余按音节升序（反查据此返回首选读音）。
    char_rows.sort_by(|a, b| {
        a.1.cmp(&b.1)
            .then_with(|| b.3.cmp(&a.3))
            .then_with(|| a.0.cmp(&b.0))
    });
    write_file(&chars_out, &render_chars(&char_rows))?;

    // ---- 词表：拼音 → 词 ----
    // 主源 jieba（词频），拼音由 D5 首选读音逐字拼接；再用 D4 权威拼音覆盖。
    let mut words: BTreeMap<String, (String, i32)> = BTreeMap::new();
    let mut derived = 0usize;
    for (word, freq) in &jieba {
        let chars: Vec<char> = word.chars().collect();
        if chars.len() < 2 || !chars.iter().all(|&c| is_han(c)) {
            continue;
        }
        let mut sylls: Vec<&str> = Vec::with_capacity(chars.len());
        let mut ok = true;
        for c in &chars {
            match primary.get(c) {
                Some(s) => sylls.push(s.as_str()),
                None => {
                    ok = false;
                    break;
                }
            }
        }
        if ok && !sylls.is_empty() {
            words.insert(word.clone(), (sylls.join(" "), *freq as i32));
            derived += 1;
        }
    }

    let mut d4_overrides = 0usize;
    let mut d4_only = 0usize;
    for (word, pinyin) in &d4 {
        let weight = jieba.get(word).copied().unwrap_or(DEFAULT_WEIGHT as u32) as i32;
        match words.get_mut(word) {
            Some(entry) => {
                entry.0 = pinyin.clone();
                d4_overrides += 1;
            }
            None => {
                words.insert(word.clone(), (pinyin.clone(), weight));
                d4_only += 1;
            }
        }
    }

    let mut word_rows: Vec<(String, String, i32)> = words
        .iter()
        .map(|(w, (p, f))| (p.clone(), w.clone(), *f))
        .collect();
    word_rows.sort_by(|a, b| a.0.cmp(&b.0).then(b.2.cmp(&a.2)).then(a.1.cmp(&b.1)));
    write_file(&words_out, &render_words(&word_rows))?;

    let report = render_report(
        &root,
        &d5_path,
        &d4_path,
        &jieba_path,
        char_rows.len(),
        word_rows.len(),
        derived,
        d4_overrides,
        d4_only,
    );
    write_file(&report_out, &report)?;

    print!("{report}");
    println!("\n→ 字表已写入 {}", chars_out.display());
    println!("→ 词表已写入 {}", words_out.display());
    println!("→ 报告已写入 {}", report_out.display());
    Ok(())
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

/// 解析 D5（`U+XXXX: pinyin1,pinyin2  # 字`），返回 (字, 无调读音列表)。
fn parse_d5(input: &str) -> Result<Vec<D5Entry>, Box<dyn Error>> {
    let mut out = Vec::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let hash = line
            .find(" # ")
            .ok_or_else(|| format!("D5 第 {lineno} 行缺少字列：{line}"))?;
        let left = &line[..hash];
        let char_str = line[hash + 3..].trim();
        let ch = single_char(char_str, "D5", lineno)?;
        let pinyin_part = left
            .split_once(':')
            .ok_or_else(|| format!("D5 第 {lineno} 行缺少码点：{line}"))?
            .1
            .trim();
        let mut readings = Vec::new();
        for reading in pinyin_part.split(',') {
            let r = reading.trim();
            if let Some(s) = strip_tones(r) {
                if !s.is_empty() && !readings.contains(&s) {
                    readings.push(s);
                }
            }
        }
        if readings.is_empty() {
            continue;
        }
        out.push((ch, readings));
    }
    Ok(out)
}

/// 解析 D4（`词: py py py`），返回 (词, 无调空格分隔拼音)；跳过非纯汉字词。
fn parse_d4(input: &str) -> Result<Vec<(String, String)>, Box<dyn Error>> {
    let mut out = Vec::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (word, pinyin) = line
            .split_once(':')
            .ok_or_else(|| format!("D4 第 {lineno} 行缺少冒号：{line}"))?;
        let word = word.trim();
        if word.chars().count() < 2 || !word.chars().all(is_han) {
            continue;
        }
        let mut sylls = Vec::new();
        for token in pinyin.split_whitespace() {
            match strip_tones(token) {
                Some(s) if !s.is_empty() => sylls.push(s),
                _ => {
                    sylls.clear();
                    break;
                }
            }
        }
        if !sylls.is_empty() {
            out.push((word.to_string(), sylls.join(" ")));
        }
    }
    Ok(out)
}

/// 解析 jieba `dict.txt`（`词 频次 [词性]`），返回词 → 最大频次。
fn parse_jieba(input: &str) -> Result<HashMap<String, u32>, Box<dyn Error>> {
    let mut map = HashMap::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split_whitespace();
        let word = fields
            .next()
            .ok_or_else(|| format!("jieba 第 {lineno} 行缺少词：{line}"))?;
        let freq_field = fields
            .next()
            .ok_or_else(|| format!("jieba 第 {lineno} 行缺少频次：{line}"))?;
        let freq: u32 = freq_field
            .parse()
            .map_err(|e| format!("jieba 第 {lineno} 行频次非法：{freq_field}（{e}）"))?;
        match map.get(word) {
            Some(&old) if old >= freq => {}
            _ => {
                map.insert(word.to_string(), freq);
            }
        }
    }
    Ok(map)
}

fn single_char(field: &str, label: &str, lineno: usize) -> Result<char, Box<dyn Error>> {
    let mut chars = field.chars();
    let ch = chars
        .next()
        .ok_or_else(|| format!("{label} 第 {lineno} 行字列为空"))?;
    if chars.next().is_some() {
        return Err(format!("{label} 第 {lineno} 行字列不是单字符：{field}").into());
    }
    Ok(ch)
}

fn is_han(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}')
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

fn render_chars(rows: &[(String, char, i32, bool)]) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 萤火虫输入法 拼音单字表（自建，CC-BY-SA-4.0，ADR-014）"
    );
    let _ = writeln!(
        out,
        "# 由 crates/ime-pinyin/examples/generate.rs 生成；拼音去声调、ü→v。"
    );
    let _ = writeln!(
        out,
        "# 来源：mozillazg/pinyin-data（MIT，D5）+ fxsjy/jieba 词频（MIT，D10）。"
    );
    let _ = writeln!(
        out,
        "# weight = jieba 单字词频（缺者 {DEFAULT_WEIGHT}）；每字首选读音（D5 首条）在前。"
    );
    let _ = writeln!(out, "# 音节\t字\tweight");
    for (syllable, ch, weight, _primary) in rows {
        let _ = writeln!(out, "{syllable}\t{ch}\t{weight}");
    }
    out
}

fn render_words(rows: &[(String, String, i32)]) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 萤火虫输入法 拼音词表（自建，CC-BY-SA-4.0，ADR-014）"
    );
    let _ = writeln!(
        out,
        "# 由 crates/ime-pinyin/examples/generate.rs 生成；拼音去声调、ü→v、空格分隔。"
    );
    let _ = writeln!(
        out,
        "# 词表主源 jieba（MIT，D10）；词拼音由 pinyin-data（MIT，D5）逐字拼接，"
    );
    let _ = writeln!(
        out,
        "# 再用 phrase-pinyin-data（MIT，D4）权威拼音覆盖多音字词。"
    );
    let _ = writeln!(
        out,
        "# weight = jieba 词频（缺者 {DEFAULT_WEIGHT}）；同拼音内按权重降序。"
    );
    let _ = writeln!(out, "# 拼音(空格分隔)\t词\tweight");
    for (pinyin, word, weight) in rows {
        let _ = writeln!(out, "{pinyin}\t{word}\t{weight}");
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn render_report(
    root: &Path,
    d5_path: &Path,
    d4_path: &Path,
    jieba_path: &Path,
    char_rows: usize,
    word_rows: usize,
    derived: usize,
    d4_overrides: usize,
    d4_only: usize,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# 拼音兜底数据生成报告（T-M2-02）");
    let _ = writeln!(out, "#");
    let _ = writeln!(out, "# D5  {}", display_path(root, d5_path));
    let _ = writeln!(out, "# D4  {}", display_path(root, d4_path));
    let _ = writeln!(out, "# D10 {}", display_path(root, jieba_path));
    let _ = writeln!(out);
    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "char_rows = {char_rows}");
    let _ = writeln!(out, "word_rows = {word_rows}");
    let _ = writeln!(out, "words_derived_from_d5 = {derived}");
    let _ = writeln!(out, "words_pinyin_overridden_by_d4 = {d4_overrides}");
    let _ = writeln!(out, "words_added_from_d4_only = {d4_only}");
    out
}

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")))
}

fn display_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .display()
        .to_string()
}

fn write_file(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("创建目录失败（{}）：{e}", parent.display()))?;
    }
    fs::write(path, content).map_err(|e| format!("写入失败（{}）：{e}", path.display()))?;
    Ok(())
}
