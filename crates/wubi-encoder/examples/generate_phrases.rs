//! T-M1-06：由「词表 + 单字码表」按五笔86 词组规则自动生成词组码表。
//!
//! 规则（公开标准，勿改，见 `docs/tasks/T-M1-06.md`）：
//! - 2 字词：每字取前 2 码 `AaAbBaBb`；
//! - 3 字词：1字首 + 2字首 + 3字首 + 3字次 `AaBaCaCb`；
//! - 4 字及以上：1字首 + 2字首 + 3字首 + 末字首 `AaBaCaZa`。
//!
//! 输入：
//!   - 词表：`data/sources/phrase-pinyin-data-pinyin.txt`（D4，MIT，`词: 拼音`）；
//!     仅取中文词，含非汉字的词条跳过。
//!   - 单字码表：`data/generated/wubi86-single.tsv`（T-M1-05 产物，`code\t字\tweight`）。
//!
//! 输出：`data/generated/wubi86-phrases.tsv`（`code\t词组`）。
//!
//! 去重（见卡步骤 3）：同一词组只保留一个码；同一码若发生规则碰撞，保留
//! **临时权重**较高的词组。临时权重 = 组成字在单字码表中的临时权重之和
//! （T-M1-07 接入真实词频后替换）。
//!
//! 先运行 `./data/sources/fetch-phrase-pinyin.sh` 下载词表（不入库）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example generate_phrases
//! 可选位置参数覆盖路径：`... -- <词表> <单字码表> <词组码表输出>`。

use std::collections::{BTreeMap, HashSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use wubi_encoder::encode_phrase;

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let words_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/phrase-pinyin-data-pinyin.txt"));
    let single_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-single.tsv"));
    let out_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-phrases.tsv"));

    let words_text = fs::read_to_string(&words_path)
        .map_err(|e| format!("读取词表失败（{}）：{e}", words_path.display()))?;
    let single_text = fs::read_to_string(&single_path)
        .map_err(|e| format!("读取单字码表失败（{}）：{e}", single_path.display()))?;

    let single = parse_single(&single_text)?;
    let stats = generate(&words_text, &single);
    write_file(&out_path, &render_tsv(&stats.phrases))?;

    print_stats(&stats);
    println!("\n→ 词组码表已写入 {}", out_path.display());
    Ok(())
}

/// 单字码表：字 → 全码，字 → 临时权重。
#[derive(Default)]
struct SingleTable {
    codes: BTreeMap<char, String>,
    weights: BTreeMap<char, u32>,
}

/// 生成结果与统计。
struct Stats {
    /// 码 → 词组（每码唯一，已按权重去重）。
    phrases: BTreeMap<String, String>,
    words_total: usize,
    words_unique: usize,
    dup_words: usize,
    skipped_non_chinese: usize,
    skipped_missing_chars: usize,
    generated: usize,
    dropped_on_collision: usize,
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

/// 解析单字码表 `code\t字\tweight`；忽略注释与空行。
fn parse_single(input: &str) -> Result<SingleTable, Box<dyn Error>> {
    let mut table = SingleTable::default();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let code = fields.next().unwrap_or_default().trim();
        let ch_field = fields.next().unwrap_or_default().trim();
        let weight_field = fields.next().unwrap_or_default().trim();
        if code.is_empty() || ch_field.is_empty() || weight_field.is_empty() {
            return Err(format!("单字码表第 {lineno} 行缺列：{line}").into());
        }
        let ch = single_char(ch_field, "单字码表", lineno)?;
        let weight: u32 = weight_field
            .parse()
            .map_err(|e| format!("单字码表第 {lineno} 行权重非法：{weight_field}（{e}）"))?;
        table.codes.insert(ch, code.to_string());
        table.weights.insert(ch, weight);
    }
    if table.codes.is_empty() {
        return Err("单字码表为空".into());
    }
    Ok(table)
}

/// 从词表行 `词: 拼音` 提取词；跳过注释/空行。
///
/// 返回 `(按出现顺序去重后的词, 解析到的词条总数)`。
fn parse_words(input: &str) -> (Vec<String>, usize) {
    let mut words = Vec::new();
    let mut seen = HashSet::new();
    let mut total = 0usize;
    for raw in input.lines() {
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let word = match line.split_once(':') {
            Some((word, _)) => word.trim(),
            None => continue,
        };
        if word.is_empty() {
            continue;
        }
        total += 1;
        if seen.insert(word.to_string()) {
            words.push(word.to_string());
        }
    }
    (words, total)
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

/// 是否为汉字（CJK 统一表意文字 / 扩展 A）。
fn is_han(c: char) -> bool {
    matches!(c, '\u{4E00}'..='\u{9FFF}' | '\u{3400}'..='\u{4DBF}')
}

// ---------------------------------------------------------------------------
// 生成
// ---------------------------------------------------------------------------

/// 按规则生成词组码表（含去重与统计）。
fn generate(words_text: &str, single: &SingleTable) -> Stats {
    let (words, words_total) = parse_words(words_text);
    let dup_words = words_total - words.len();

    let mut best: BTreeMap<String, (u64, usize, String)> = BTreeMap::new();
    let mut skipped_non_chinese = 0usize;
    let mut skipped_missing_chars = 0usize;
    let mut generated = 0usize;

    for (order, word) in words.iter().enumerate() {
        if !word.chars().all(is_han) {
            skipped_non_chinese += 1;
            continue;
        }
        let Some(codes) = full_codes(word, single) else {
            skipped_missing_chars += 1;
            continue;
        };
        let code_refs: Vec<&str> = codes.iter().map(String::as_str).collect();
        let Ok(code) = encode_phrase(&code_refs) else {
            skipped_missing_chars += 1;
            continue;
        };
        generated += 1;
        let weight = temp_weight(word, single);
        match best.get(&code) {
            Some((current, _, _)) if *current >= weight => {}
            _ => {
                best.insert(code, (weight, order, word.clone()));
            }
        }
    }

    let phrases: BTreeMap<String, String> = best
        .into_iter()
        .map(|(code, (_, _, word))| (code, word))
        .collect();
    Stats {
        dropped_on_collision: generated - phrases.len(),
        phrases,
        words_total,
        words_unique: words.len(),
        dup_words,
        skipped_non_chinese,
        skipped_missing_chars,
        generated,
    }
}

/// 返回词中每个字的全码；任一字不在单字码表中则返回 `None`。
fn full_codes(word: &str, single: &SingleTable) -> Option<Vec<String>> {
    word.chars()
        .map(|c| single.codes.get(&c).cloned())
        .collect::<Option<Vec<_>>>()
}

/// 临时权重：组成字在单字码表中的临时权重之和（T-M1-07 之前占位）。
fn temp_weight(word: &str, single: &SingleTable) -> u64 {
    word.chars()
        .filter_map(|c| single.weights.get(&c))
        .map(|w| u64::from(*w))
        .sum()
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

/// 渲染词组码表：`code\t词组`。
fn render_tsv(phrases: &BTreeMap<String, String>) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 萤火虫输入法 五笔86 词组码表（自建，CC-BY-SA-4.0，ADR-014）"
    );
    let _ = writeln!(
        out,
        "# 由 crates/wubi-encoder/examples/generate_phrases.rs 生成；词组规则为公开标准（ADR-016）。"
    );
    let _ = writeln!(
        out,
        "# 词表来源：phrase-pinyin-data pinyin.txt（MIT，mozillazg）；详见 data/sources.toml D4。"
    );
    let _ = writeln!(
        out,
        "# 同码去重采用临时权重（组成字临时权重之和）；正式词频待 D7（ADR-013）。"
    );
    let _ = writeln!(out, "# code\t词组");
    for (code, word) in phrases {
        let _ = writeln!(out, "{code}\t{word}");
    }
    out
}

fn print_stats(stats: &Stats) {
    println!("[summary]");
    println!("words_total = {}", stats.words_total);
    println!("words_unique = {}", stats.words_unique);
    println!("dup_words = {}", stats.dup_words);
    println!("phrases_generated = {}", stats.generated);
    println!("phrases_written = {}", stats.phrases.len());
    println!("skipped_non_chinese = {}", stats.skipped_non_chinese);
    println!("skipped_missing_chars = {}", stats.skipped_missing_chars);
    println!("dropped_on_collision = {}", stats.dropped_on_collision);
}

fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")))
}

fn write_file(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("创建目录失败（{}）：{e}", parent.display()))?;
    }
    fs::write(path, content).map_err(|e| format!("写入失败（{}）：{e}", path.display()))?;
    Ok(())
}
