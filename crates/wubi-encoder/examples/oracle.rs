//! 五笔86 合体字 + 末笔字型识别码 oracle 全量对照（T-M1-03）。
//!
//! 数据来源（详见 `docs/数据来源与许可.md`、`docs/tasks/T-M1-03.md`）：
//!   - oracle：`data/sources/windinput-wubi86-chaizi.txt`（D3，MIT；按 ADR-016 仅验证、不发布）
//!   - 常用字范围：`data/generated/gb2312-level1.txt`（GB2312 一级 3755 字）
//!
//! 方法（ADR-017）：
//!   1. D3 第 2 列与第 3 列（编码）逐位等长，是"每码位一个字根/笔画/识别码字形"，
//!      故从 D3 逐位推导「字形 → 键」映射（多数表决，列出歧义字形）；
//!   2. 三码字 = 2 字根 + 识别码：从末位反推 (末笔, 结构)，再用本库规则重编码对照；
//!   3. 四码字按 ≥4 字根规则（键 1、2、3、末）重编码对照（成字字根的字形含笔画，
//!      同样落在该规则内）；
//!   4. 键名字（25 个）按 `encode_key_name` 对照。
//!
//! 注意：识别码表是公开规范（本库 `recognition_key`），其正确性由单测中的规范样例
//! （中/和/对/地/要/会）独立校核，不依赖 D3；本工具验证的是"规则与 D3 全量自洽"。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example oracle
//! 可选位置参数覆盖路径：`... -- <d3> <gb2312> <report> <derived-tsv>`。

use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

use wubi_encoder::{
    encode_hechengzi, encode_key_name, EncodeError, RadicalTable, Stroke, Structure,
};

/// 键名字（五笔86 固定 25 字）。
const KEY_NAMES: &str = "王土大木工目日口田山禾白月人金言立水火之已子女又纟";

/// 识别码 → (末笔, 结构) 的逆映射（识别码表是 5×3 双射）。
fn inverse_recognition(key: char) -> Option<(Stroke, Structure)> {
    match key {
        'g' => Some((Stroke::Heng, Structure::LeftRight)),
        'f' => Some((Stroke::Heng, Structure::UpDown)),
        'd' => Some((Stroke::Heng, Structure::Mixed)),
        'h' => Some((Stroke::Shu, Structure::LeftRight)),
        'j' => Some((Stroke::Shu, Structure::UpDown)),
        'k' => Some((Stroke::Shu, Structure::Mixed)),
        't' => Some((Stroke::Pie, Structure::LeftRight)),
        'r' => Some((Stroke::Pie, Structure::UpDown)),
        'e' => Some((Stroke::Pie, Structure::Mixed)),
        'y' => Some((Stroke::Na, Structure::LeftRight)),
        'u' => Some((Stroke::Na, Structure::UpDown)),
        'i' => Some((Stroke::Na, Structure::Mixed)),
        'n' => Some((Stroke::Zhe, Structure::LeftRight)),
        'b' => Some((Stroke::Zhe, Structure::UpDown)),
        'v' => Some((Stroke::Zhe, Structure::Mixed)),
        _ => None,
    }
}

fn structure_label(s: Structure) -> &'static str {
    match s {
        Structure::LeftRight => "left-right",
        Structure::UpDown => "up-down",
        Structure::Mixed => "mixed",
    }
}

fn stroke_label(s: Stroke) -> &'static str {
    match s {
        Stroke::Heng => "heng",
        Stroke::Shu => "shu",
        Stroke::Pie => "pie",
        Stroke::Na => "na",
        Stroke::Zhe => "zhe",
    }
}

struct Record {
    ch: char,
    glyphs: Vec<char>,
    code: String,
}

struct Stats {
    total: usize,
    matched: usize,
    total_gb1: usize,
    matched_gb1: usize,
    total_three: usize,
    matched_three: usize,
    distinct_glyphs: usize,
}

fn parse_d3(input: &str) -> Result<Vec<Record>, Box<dyn Error>> {
    let mut out = Vec::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let ch_field = fields.next().unwrap_or_default();
        let glyph_field = fields
            .next()
            .ok_or_else(|| format!("D3 第 {lineno} 行缺少制表符：{line}"))?;
        let code = fields
            .next()
            .ok_or_else(|| format!("D3 第 {lineno} 行缺少编码列：{line}"))?
            .trim()
            .to_string();
        let mut chs = ch_field.chars();
        let ch = chs
            .next()
            .ok_or_else(|| format!("D3 第 {lineno} 行字列为空"))?;
        if chs.next().is_some() {
            return Err(format!("D3 第 {lineno} 行字列不是单字符：{ch_field}").into());
        }
        let glyphs: Vec<char> = glyph_field
            .split_whitespace()
            .flat_map(|t| t.chars())
            .collect();
        if glyphs.is_empty() || glyphs.len() != code.len() {
            return Err(format!("D3 第 {lineno} 行字形列与编码列长度不一致：{line}").into());
        }
        out.push(Record { ch, glyphs, code });
    }
    Ok(out)
}

/// 逐位推导「字形 → 键」，多数表决；返回 (映射, 歧义字形清单)。
fn derive_glyph_keys(
    records: &[Record],
) -> (BTreeMap<char, char>, BTreeMap<char, BTreeMap<char, usize>>) {
    let mut counts: BTreeMap<char, BTreeMap<char, usize>> = BTreeMap::new();
    for rec in records {
        for (glyph, key) in rec.glyphs.iter().zip(rec.code.chars()) {
            *counts.entry(*glyph).or_default().entry(key).or_insert(0) += 1;
        }
    }
    let mut mapping = BTreeMap::new();
    let mut ambiguous = BTreeMap::new();
    for (glyph, key_counts) in &counts {
        let best = key_counts
            .iter()
            .max_by_key(|(_, c)| **c)
            .map(|(k, _)| *k)
            .unwrap();
        mapping.insert(*glyph, best);
        if key_counts.len() > 1 {
            ambiguous.insert(*glyph, key_counts.clone());
        }
    }
    (mapping, ambiguous)
}

/// 用字形→键映射构造 RadicalTable（TSV 形式喂给 from_tsv）。
fn build_table(mapping: &BTreeMap<char, char>) -> Result<RadicalTable, EncodeError> {
    let mut by_key: BTreeMap<char, Vec<char>> = BTreeMap::new();
    for (glyph, key) in mapping {
        by_key.entry(*key).or_default().push(*glyph);
    }
    let mut tsv = String::new();
    for (key, glyphs) in &by_key {
        let glyphs: Vec<String> = glyphs.iter().map(|g| g.to_string()).collect();
        tsv.push(*key);
        tsv.push('\t');
        tsv.push_str(&glyphs.join(","));
        tsv.push('\n');
    }
    RadicalTable::from_tsv(&tsv)
}

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let d3_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/windinput-wubi86-chaizi.txt"));
    let gb_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/gb2312-level1.txt"));
    let report_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/oracle-report.txt"));
    let derived_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-structure-laststroke.tsv"));

    let d3_text = fs::read_to_string(&d3_path)
        .map_err(|e| format!("读取 D3 失败（{}）：{e}", d3_path.display()))?;
    let records = parse_d3(&d3_text)?;

    let (mapping, ambiguous) = derive_glyph_keys(&records);
    let table = build_table(&mapping)?;

    let key_names: BTreeSet<char> = KEY_NAMES.chars().collect();
    let gb1: BTreeSet<char> = match fs::read_to_string(&gb_path) {
        Ok(text) => text.chars().filter(|c| *c != '\n' && *c != '\r').collect(),
        Err(_) => BTreeSet::new(),
    };

    // 归因统计。
    let mut total = 0usize;
    let mut matched = 0usize;
    let mut total_gb1 = 0usize;
    let mut matched_gb1 = 0usize;
    let mut total_three = 0usize;
    let mut matched_three = 0usize;
    let mut by_reason: BTreeMap<&'static str, usize> = BTreeMap::new();
    let mut mismatch_samples: Vec<(char, String, String, String)> = Vec::new();

    // 派生结构/末笔数据集（仅三码字：按「2 字根 + 识别码」反推；见头部说明）。
    let mut derived = String::new();
    derived.push_str(
        "# 结构/末笔数据集（PROVISIONAL，T-M1-03 派生，勿直接用于发布）\n\
# 派生规则：三码字 = 键1 键2 识别码 → 由识别码反推 (末笔, 结构)。\n\
# ⚠️ 仅对「2 字根 + 识别码」的合体字有效；三码字中混有「成字字根」（键+首笔+次笔），\n\
#    其末位不是识别码，故本表对这类字的结构/末笔是错的。\n\
# 可靠的结构/末笔需可靠的拆字数据（待 T-M1-05 引入独立来源）。\n\
# char\tstructure\tlast_stroke\twubi_code\n",
    );

    for rec in &records {
        total += 1;
        let is_gb1 = gb1.contains(&rec.ch);
        if is_gb1 {
            total_gb1 += 1;
        }

        let (expected, reason) = encode_record(rec, &table, &key_names);

        let ok = expected.as_deref() == Some(rec.code.as_str());
        if ok {
            matched += 1;
            if is_gb1 {
                matched_gb1 += 1;
            }
            if rec.code.len() == 3 {
                matched_three += 1;
            }
        } else {
            let base_reason = reason.unwrap_or("rule-mismatch");
            let reason = if rec.glyphs.iter().any(|g| ambiguous.contains_key(g)) {
                "ambiguous-glyph"
            } else {
                base_reason
            };
            *by_reason.entry(reason).or_insert(0) += 1;
            if mismatch_samples.len() < 200 {
                mismatch_samples.push((
                    rec.ch,
                    rec.code.clone(),
                    expected.unwrap_or_else(|| "<error>".to_string()),
                    reason.to_string(),
                ));
            }
        }

        if rec.code.len() == 3 {
            total_three += 1;
            if let Some((stroke, structure)) = rec.code.chars().last().and_then(inverse_recognition)
            {
                let _ = writeln!(
                    derived,
                    "{}\t{}\t{}\t{}",
                    rec.ch,
                    structure_label(structure),
                    stroke_label(stroke),
                    rec.code
                );
            }
        }
    }

    let report = render_report(
        &Stats {
            total,
            matched,
            total_gb1,
            matched_gb1,
            total_three,
            matched_three,
            distinct_glyphs: mapping.len(),
        },
        &ambiguous,
        &by_reason,
        &mismatch_samples,
        &display_path(&root, &d3_path),
    );

    write_file(&report_path, &report)?;
    write_file(&derived_path, &derived)?;

    print!("{report}");
    println!("\n→ 报告已写入 {}", report_path.display());
    println!("→ 派生结构/末笔数据集已写入 {}", derived_path.display());
    Ok(())
}

/// 用本库规则重编码一条记录，返回 (期望编码, 失败原因)。
fn encode_record(
    rec: &Record,
    table: &RadicalTable,
    key_names: &BTreeSet<char>,
) -> (Option<String>, Option<&'static str>) {
    // 键名字：4 个相同键位 + 属于 25 键名。
    let first = rec.code.chars().next();
    if rec.code.len() == 4
        && rec.code.chars().all(|c| Some(c) == first)
        && key_names.contains(&rec.ch)
    {
        if let Some(key) = first {
            return (Some(encode_key_name(key)), None);
        }
    }

    if rec.code.len() == 3 {
        // 三码字按标准全码规则视为「2 字根 + 识别码」：前两个字形是字根，
        // 末位是识别码。注意：D3 中少量三码字实为三/多字根的简码，
        // 其末位是字根而非识别码（见报告与 T-M1-03 结论）。
        let key = match rec.code.chars().last() {
            Some(k) => k,
            None => return (None, Some("empty-code")),
        };
        let (stroke, structure) = match inverse_recognition(key) {
            Some(pair) => pair,
            None => return (None, Some("invalid-recognition-key")),
        };
        let radicals: Vec<String> = rec.glyphs[..2].iter().map(|g| g.to_string()).collect();
        match encode_hechengzi(&radicals, structure, stroke, table) {
            Ok(code) => (Some(code), None),
            Err(_) => (None, Some("unknown-glyph")),
        }
    } else {
        // 4 码：≥4 字根（成字字根的字形含笔画，同样落在此规则）。
        // 结构/末笔仅对 2/3 字根有意义，此处取任意合法值即可（不参与编码）。
        let radicals: Vec<String> = rec.glyphs.iter().map(|g| g.to_string()).collect();
        match encode_hechengzi(&radicals, Structure::Mixed, Stroke::Heng, table) {
            Ok(code) => (Some(code), None),
            Err(_) => (None, Some("unknown-glyph")),
        }
    }
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

fn render_report(
    stats: &Stats,
    ambiguous: &BTreeMap<char, BTreeMap<char, usize>>,
    by_reason: &BTreeMap<&'static str, usize>,
    mismatch_samples: &[(char, String, String, String)],
    d3_label: &str,
) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 五笔86 合体字 + 末笔字型识别码 oracle 对照报告（T-M1-03）"
    );
    let _ = writeln!(out, "#");
    let _ = writeln!(out, "# oracle = {d3_label}");
    let _ = writeln!(
        out,
        "# 方法（ADR-017）：从 D3 逐位推导字形→键映射；三码字按「2 字根 + 识别码」反推 (末笔, 结构)"
    );
    let _ = writeln!(
        out,
        "# 后重编码对照；四码字按 ≥4 字根规则对照；键名字按 encode_key_name 对照。"
    );
    let _ = writeln!(
        out,
        "# 本质：规则与 D3 全量**自洽**检验（非独立数据检验）；识别码表本身由单测中的规范样例独立校核。"
    );
    let _ = writeln!(
        out,
        "# ⚠️ D3 第 2 列是「每码位字形」而非纯拆字，不给出字根数；三码字中混有成字字根，其末位非识别码。"
    );
    let _ = writeln!(out);
    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "records = {}", stats.total);
    let _ = writeln!(out, "matched = {}", stats.matched);
    let _ = writeln!(out, "consistency = {:.4}%", pct(stats.matched, stats.total));
    let _ = writeln!(
        out,
        "gb2312_level1_consistency = {:.4}% ({}/{})",
        pct(stats.matched_gb1, stats.total_gb1),
        stats.matched_gb1,
        stats.total_gb1
    );
    let _ = writeln!(
        out,
        "three_code_consistency = {:.4}% ({}/{})",
        pct(stats.matched_three, stats.total_three),
        stats.matched_three,
        stats.total_three
    );
    let _ = writeln!(out, "distinct_glyphs = {}", stats.distinct_glyphs);
    let _ = writeln!(out, "ambiguous_glyphs = {}", ambiguous.len());

    let _ = writeln!(out);
    let _ = writeln!(out, "[mismatch_reasons]");
    for (reason, count) in by_reason {
        let _ = writeln!(out, "{reason} = {count}");
    }

    let _ = writeln!(out);
    let _ = writeln!(out, "[ambiguous_glyphs]");
    let _ = writeln!(out, "# glyph\tkey_counts");
    for (glyph, key_counts) in ambiguous {
        let counts: Vec<String> = key_counts.iter().map(|(k, c)| format!("{k}:{c}")).collect();
        let _ = writeln!(out, "<U+{:04X}>\t{}", *glyph as u32, counts.join(" "));
    }

    let _ = writeln!(out);
    let _ = writeln!(out, "[mismatch_samples]");
    let _ = writeln!(out, "# char\toracle\tactual\treason");
    for (ch, oracle, actual, reason) in mismatch_samples {
        let _ = writeln!(out, "{ch}\t{oracle}\t{actual}\t{reason}");
    }

    out
}

fn pct(part: usize, whole: usize) -> f64 {
    if whole == 0 {
        100.0
    } else {
        part as f64 * 100.0 / whole as f64
    }
}

fn write_file(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = fs::File::create(path)?;
    file.write_all(content.as_bytes())?;
    Ok(())
}
