//! T-M1-06b：由 jieba 词表（D10）+ 单字码表生成五笔86 词组码表（含真实词频权重）。
//!
//! 规则（公开标准，勿改，见 `docs/tasks/T-M1-06.md`）：
//! - 2 字词：每字取前 2 码 `AaAbBaBb`；
//! - 3 字词：1字首 + 2字首 + 3字首 + 3字次 `AaBaCaCb`；
//! - 4 字及以上：1字首 + 2字首 + 3字首 + 末字首 `AaBaCaZa`。
//!
//! 输入：
//!   - 词表：`data/sources/jieba-dict.txt`（D10，MIT，`词 频次 词性`）；
//!   - 单字码表：`data/generated/wubi86-single.tsv`（T-M1-05 产物，`code\t字\tweight`）。
//!
//! 输出：`data/generated/wubi86-phrases.tsv`（`code\t词组\tweight`）；
//! 报告：`data/generated/wubi86-phrases-report.txt`。
//!
//! 过滤：只保留**纯汉字词**（含字母/数字/符号者跳过），长度 2–10。
//! 权重：`weight` = jieba 中该词的频次（**真实词频**，ADR-013）。
//! 多候选：一个码可对应多个词（重码），**全部保留**并按 `weight` 降序
//! （见 `docs/技术方案.md` §6.2 重码模型；T-M1-07 依赖此顺序做候选排序）。
//!
//! 先运行 `./data/sources/fetch-jieba-dict.sh` 下载词表（不入库）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example generate_phrases
//! 可选位置参数覆盖路径：`... -- <词表> <单字码表> <词组码表输出> <报告输出>`。

use std::collections::BTreeMap;
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use wubi_encoder::encode_phrase;

#[path = "support/jieba.rs"]
mod jieba;

/// 验收要求的必需样本词：生成结果必须全部存在。
const REQUIRED_WORDS: &[&str] = &[
    "世界",
    "人民",
    "中文",
    "输入法",
    "计算机",
    "经济学",
    "图书馆",
    "中华人民共和国",
];

/// 必需样本中写死码的校验（`docs/tasks/T-M1-06.md`）：`中华人民共和国 → kwwl`。
const REQUIRED_KNOWN: &[(&str, &str)] = &[("中华人民共和国", "kwwl")];

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let words_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/jieba-dict.txt"));
    let single_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-single.tsv"));
    let out_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-phrases.tsv"));
    let report_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-phrases-report.txt"));

    let words_text = fs::read_to_string(&words_path)
        .map_err(|e| format!("读取词表失败（{}）：{e}", words_path.display()))?;
    let single_text = fs::read_to_string(&single_path)
        .map_err(|e| format!("读取单字码表失败（{}）：{e}", single_path.display()))?;

    let single = parse_single(&single_text)?;
    let entries = jieba::parse(&words_text)
        .map_err(|e| format!("解析 jieba 词表失败（{}）：{e}", words_path.display()))?;

    let stats = generate(&entries, &single);
    verify_required(&stats)?;
    write_file(&out_path, &render_tsv(&stats.rows))?;

    let report = render_report(&words_path, &single_path, &out_path, &stats);
    write_file(&report_path, &report)?;

    print!("{report}");
    println!("\n→ 词组码表已写入 {}", out_path.display());
    println!("→ 报告已写入 {}", report_path.display());
    Ok(())
}

/// 单字码表：字 → 全码。
#[derive(Default)]
struct SingleTable {
    codes: BTreeMap<char, String>,
}

/// 生成结果与统计。
struct Stats {
    /// 码 → 候选列表（词, 频次）；已按权重降序（等权按词升序）。
    rows: BTreeMap<String, Vec<(String, u32)>>,
    jieba_entries: usize,
    words_kept: usize,
    skipped_single_char: usize,
    skipped_too_long: usize,
    skipped_non_chinese: usize,
    skipped_missing_chars: usize,
    phrases_generated: usize,
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
        weight_field
            .parse::<u32>()
            .map_err(|e| format!("单字码表第 {lineno} 行权重非法：{weight_field}（{e}）"))?;
        table.codes.insert(ch, code.to_string());
    }
    if table.codes.is_empty() {
        return Err("单字码表为空".into());
    }
    Ok(table)
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

// ---------------------------------------------------------------------------
// 生成
// ---------------------------------------------------------------------------

/// 按规则生成词组码表（过滤 + 分码 + 组内按词频降序）。
fn generate(entries: &[jieba::Entry], single: &SingleTable) -> Stats {
    let mut rows: BTreeMap<String, Vec<(String, u32)>> = BTreeMap::new();
    let mut skipped_single_char = 0usize;
    let mut skipped_too_long = 0usize;
    let mut skipped_non_chinese = 0usize;
    let mut skipped_missing_chars = 0usize;
    let mut phrases_generated = 0usize;

    for entry in entries {
        let len = entry.word.chars().count();
        if len < 2 {
            skipped_single_char += 1;
            continue;
        }
        if len > 10 {
            skipped_too_long += 1;
            continue;
        }
        if !entry.word.chars().all(jieba::is_han) {
            skipped_non_chinese += 1;
            continue;
        }
        let Some(codes) = full_codes(&entry.word, single) else {
            skipped_missing_chars += 1;
            continue;
        };
        let code_refs: Vec<&str> = codes.iter().map(String::as_str).collect();
        let Ok(code) = encode_phrase(&code_refs) else {
            skipped_missing_chars += 1;
            continue;
        };
        phrases_generated += 1;
        rows.entry(code)
            .or_default()
            .push((entry.word.clone(), entry.freq));
    }

    for candidates in rows.values_mut() {
        candidates.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    }

    let words_kept = entries.len()
        - skipped_single_char
        - skipped_too_long
        - skipped_non_chinese
        - skipped_missing_chars;
    Stats {
        rows,
        jieba_entries: entries.len(),
        words_kept,
        skipped_single_char,
        skipped_too_long,
        skipped_non_chinese,
        skipped_missing_chars,
        phrases_generated,
    }
}

/// 返回词中每个字的全码；任一字不在单字码表中则返回 `None`。
fn full_codes(word: &str, single: &SingleTable) -> Option<Vec<String>> {
    word.chars()
        .map(|c| single.codes.get(&c).cloned())
        .collect::<Option<Vec<_>>>()
}

/// 断言必需样本词全部存在，且写死码样本正确。
fn verify_required(stats: &Stats) -> Result<(), Box<dyn Error>> {
    let missing: Vec<&str> = REQUIRED_WORDS
        .iter()
        .copied()
        .filter(|word| find_word(stats, word).is_none())
        .collect();
    if !missing.is_empty() {
        return Err(format!("必需样本词缺失：{}", missing.join("、")).into());
    }
    for (word, expected) in REQUIRED_KNOWN {
        match find_word(stats, word) {
            Some((actual, _)) if actual == *expected => {}
            Some((actual, _)) => {
                return Err(format!("必需样本 {word} 的码应为 {expected}，实际 {actual}").into());
            }
            None => return Err(format!("必需样本词缺失：{word}").into()),
        }
    }
    Ok(())
}

/// 在结果中查找词的 `(码, 权重)`。
fn find_word<'a>(stats: &'a Stats, word: &str) -> Option<(&'a str, u32)> {
    for (code, candidates) in &stats.rows {
        for (candidate, weight) in candidates {
            if candidate == word {
                return Some((code.as_str(), *weight));
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

/// 渲染词组码表：`code\t词组\tweight`（码升序；同码内权重降序）。
fn render_tsv(rows: &BTreeMap<String, Vec<(String, u32)>>) -> String {
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
        "# 词表与词频来源：fxsjy/jieba dict.txt（MIT）；详见 data/sources.toml D10。"
    );
    let _ = writeln!(
        out,
        "# weight = jieba 词频（真实词频，ADR-013）；同一 code 的多个候选按 weight 降序。"
    );
    let _ = writeln!(out, "# code\t词组\tweight");
    for (code, candidates) in rows {
        for (word, weight) in candidates {
            let _ = writeln!(out, "{code}\t{word}\t{weight}");
        }
    }
    out
}

fn render_report(words_path: &Path, single_path: &Path, out_path: &Path, stats: &Stats) -> String {
    let root = workspace_root();
    let multi = stats.rows.values().filter(|c| c.len() > 1).count();
    let rows_written: usize = stats.rows.values().map(Vec::len).sum();

    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 词组码表生成报告（T-M1-06b）");
    let _ = writeln!(out, "#");
    let _ = writeln!(
        out,
        "# 词表/词频：{}（D10，MIT）",
        display_path(&root, words_path)
    );
    let _ = writeln!(
        out,
        "# 单字码表：{}（T-M1-05）",
        display_path(&root, single_path)
    );
    let _ = writeln!(out, "# 输出：{}", display_path(&root, out_path));
    let _ = writeln!(out);
    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "jieba_entries = {}", stats.jieba_entries);
    let _ = writeln!(out, "words_kept = {}", stats.words_kept);
    let _ = writeln!(out, "skipped_single_char = {}", stats.skipped_single_char);
    let _ = writeln!(out, "skipped_too_long = {}", stats.skipped_too_long);
    let _ = writeln!(out, "skipped_non_chinese = {}", stats.skipped_non_chinese);
    let _ = writeln!(
        out,
        "skipped_missing_chars = {}",
        stats.skipped_missing_chars
    );
    let _ = writeln!(out, "phrases_generated = {}", stats.phrases_generated);
    let _ = writeln!(out, "codes_unique = {}", stats.rows.len());
    let _ = writeln!(out, "codes_with_multi_candidates = {multi}");
    let _ = writeln!(out, "rows_written = {rows_written}");
    let _ = writeln!(out);
    let _ = writeln!(out, "[required_samples]");
    let _ = writeln!(out, "# word\tcode\tweight");
    for word in REQUIRED_WORDS {
        match find_word(stats, word) {
            Some((code, weight)) => {
                let _ = writeln!(out, "{word}\t{code}\t{weight}");
            }
            None => {
                let _ = writeln!(out, "{word}\tMISSING\t0");
            }
        }
    }
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
