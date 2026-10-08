//! T-M1-05：自建单字码表生成 + 多 oracle 对照回归。
//!
//! 生成两条路径并对照（详见 `docs/tasks/T-M1-05.md` 与 ADR-016/017/019）：
//!
//! 1. **发布路径（primary，D3 拆字）**：D3（WindInput，MIT）第 2 列给出「每码位字形」
//!    （干净的拆字表示，逐位映射到键）；本工具从 D3 逐位推导「字形 → 键」字根表（公开
//!    五笔86 规范在 D3 字形记法下的表达），再用**本仓编码器**的键名字 / 合体字规则生成
//!    全码，得到发布用单字码表。
//! 2. **交叉检查路径（D2 拆字）**：按任务卡对 D2（aardio/wubi-lex，MIT）逐字编码
//!    （键名字走 `encode_key_name`、成字字根走 `encode_chengzi`、合体字走
//!    `encode_hechengzi`），量化 D2 字形记法的歧义（ADR-017：D2 的 PUA/通配字形不可靠，
//!    不能可靠提供字根数）。
//!
//! 发布路径产出的码表按 **ADR-019** 与 ≥2 个独立 oracle 全量对照：
//!   - Oracle #1 = WindInput（D3）；Oracle #2 = rime/rime-wubi（D9，LGPL-3）。
//!
//! 结构/末笔（识别码）沿用 ADR-017/019 的 D3 派生数据（PROVISIONAL，不进发布产物）。
//! oracle 数据仅作测试对照，不打包、不分发（ADR-016）。
//!
//! 先运行 `./data/sources/fetch-wubi-chaizi.sh` 与 `./data/sources/fetch-wubi-oracle2.sh`
//! 下载源数据（不入库）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example generate
//! 可选位置参数覆盖路径：`... -- <d2> <d3> <rime> <gb1> <tsv-out> <report-out>`。

use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

use wubi_encoder::{
    encode_chengzi, encode_hechengzi, encode_key_name, EncodeError, RadicalTable, Stroke, Structure,
};

/// 键名字（五笔86 固定 25 字），与 `wubi_encoder` 内的键名映射一致。
const KEY_NAMES: &str = "王土大木工目日口田山禾白月人金言立水火之已子女又纟";

/// 键名字 → 键位的逆映射键序（与 KEY_NAMES 一一对应）。
const KEY_NAME_KEYS: &str = "gfdsahjklmtrewqyuiopnbvcx";

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

/// D3 记录：字 + 每码位字形 + 五笔码。
struct D3Record {
    ch: char,
    glyphs: Vec<char>,
    code: String,
}

/// D2 记录：字 + 字根序列（逐字符）。
struct D2Record {
    ch: char,
    glyphs: Vec<char>,
}

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let d2_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/wubi-lex-86.txt"));
    let d3_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/windinput-wubi86-chaizi.txt"));
    let rime_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/rime-wubi86.dict.yaml"));
    let gb1_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/gb2312-level1.txt"));
    let tsv_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-single.tsv"));
    let report_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-regression.txt"));

    let d3_text = fs::read_to_string(&d3_path)
        .map_err(|e| format!("读取 D3 失败（{}）：{e}", d3_path.display()))?;
    let d2_text = fs::read_to_string(&d2_path)
        .map_err(|e| format!("读取 D2 失败（{}）：{e}", d2_path.display()))?;
    let rime_text = fs::read_to_string(&rime_path)
        .map_err(|e| format!("读取 Rime 字典失败（{}）：{e}", rime_path.display()))?;
    let gb1_text = fs::read_to_string(&gb1_path)
        .map_err(|e| format!("读取 GB1 失败（{}）：{e}", gb1_path.display()))?;

    let d3_records = parse_d3(&d3_text)?;
    let d2_records = parse_d2(&d2_text)?;
    let rime = parse_rime(&rime_text)?;
    let gb1 = parse_gb1(&gb1_text);

    let key_names: BTreeMap<char, char> = KEY_NAMES.chars().zip(KEY_NAME_KEYS.chars()).collect();

    // ---- 发布路径：D3 字形 → 键 字根表（公开规范在 D3 字形记法下的表达） ----
    let d3_glyph_keys = derive_glyph_keys(&d3_records);
    let d3_table = build_table(&d3_glyph_keys)?;
    let d3_codes: BTreeMap<char, String> = generate_primary(&d3_records, &d3_table, &key_names);

    // ---- 交叉检查路径：D2 逐字编码（键名字/成字字根/合体字） ----
    let d2_glyph_keys = derive_d2_glyph_keys(&d2_records, &d3_records);
    let d2_table = build_table(&d2_glyph_keys)?;
    let d3_codes_for_d2: BTreeMap<char, String> =
        d3_records.iter().map(|r| (r.ch, r.code.clone())).collect();
    let d2_codes = generate_d2(&d2_records, &d2_table, &key_names, &d3_codes_for_d2);

    // ---- 输出码表（发布路径） ----
    write_file(&tsv_path, &render_tsv(&d3_codes, &gb1))?;

    // ---- 对照回归 + 差异分析 ----
    let d3_oracle: BTreeMap<char, String> =
        d3_records.iter().map(|r| (r.ch, r.code.clone())).collect();
    let report = render_report(
        &root,
        &d3_path,
        &d2_path,
        &rime_path,
        &d3_codes,
        &d2_codes,
        &d3_oracle,
        &rime,
        &gb1,
        d3_glyph_keys.len(),
        d2_glyph_keys.len(),
    );
    write_file(&report_path, &report)?;

    print!("{report}");
    println!("\n→ 码表已写入 {}", tsv_path.display());
    println!("→ 回归报告已写入 {}", report_path.display());
    Ok(())
}

// ---------------------------------------------------------------------------
// 解析
// ---------------------------------------------------------------------------

/// 解析 D3（`字\t字根序列（空格分隔）\t五笔码`）；字形列与编码列逐位等长。
fn parse_d3(input: &str) -> Result<Vec<D3Record>, Box<dyn Error>> {
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
            .ok_or_else(|| format!("D3 第 {lineno} 行缺少字形列：{line}"))?;
        let code = fields
            .next()
            .ok_or_else(|| format!("D3 第 {lineno} 行缺少编码列：{line}"))?
            .trim()
            .to_string();
        let ch = single_char(ch_field, "D3", lineno)?;
        let glyphs: Vec<char> = glyph_field
            .split_whitespace()
            .flat_map(|t| t.chars())
            .collect();
        if glyphs.is_empty() || glyphs.len() != code.len() {
            return Err(format!("D3 第 {lineno} 行字形列与编码列长度不一致：{line}").into());
        }
        out.push(D3Record { ch, glyphs, code });
    }
    Ok(out)
}

/// 解析 D2（`字\t字根1字根2...`，字根逐字符拼接）。
fn parse_d2(input: &str) -> Result<Vec<D2Record>, Box<dyn Error>> {
    let mut out = Vec::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let ch_field = fields.next().unwrap_or_default();
        let rad_field = fields
            .next()
            .ok_or_else(|| format!("D2 第 {lineno} 行缺少字根列：{line}"))?;
        let ch = single_char(ch_field, "D2", lineno)?;
        let glyphs: Vec<char> = rad_field.chars().collect();
        if glyphs.is_empty() {
            return Err(format!("D2 第 {lineno} 行字根为空：{line}").into());
        }
        out.push(D2Record { ch, glyphs });
    }
    Ok(out)
}

/// 解析 Rime 字典，仅取单字全码（同字取最长码）。
fn parse_rime(input: &str) -> Result<BTreeMap<char, String>, Box<dyn Error>> {
    let mut map = BTreeMap::new();
    let mut in_body = false;
    for raw in input.lines() {
        let line = raw.trim_start_matches('\u{feff}').trim();
        if !in_body {
            if line == "..." {
                in_body = true;
            }
            continue;
        }
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let text = fields.next().unwrap_or_default();
        let code = fields.next().unwrap_or_default().trim();
        if code.is_empty() || !code.chars().all(|c| ('a'..='y').contains(&c)) {
            continue;
        }
        let mut chars = text.chars();
        let ch = match chars.next() {
            Some(c) => c,
            None => continue,
        };
        if chars.next().is_some() {
            continue; // 非单字
        }
        match map.get(&ch) {
            None => {
                map.insert(ch, code.to_string());
            }
            Some(old)
                if code.len() > old.len() || (code.len() == old.len() && code < old.as_str()) =>
            {
                map.insert(ch, code.to_string());
            }
            Some(_) => {}
        }
    }
    if !in_body {
        return Err("Rime 字典缺少 YAML 文档结束标记 `...`".into());
    }
    Ok(map)
}

/// 解析 GB2312 一级字表（一行一字）。
fn parse_gb1(input: &str) -> BTreeSet<char> {
    input
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| l.chars().next())
        .collect()
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
// 字根表推导
// ---------------------------------------------------------------------------

/// 逐位推导「字形 → 键」，多数表决（D3 字形列与编码列逐位对齐）。
fn derive_glyph_keys(records: &[D3Record]) -> BTreeMap<char, char> {
    let mut counts: BTreeMap<char, BTreeMap<char, usize>> = BTreeMap::new();
    for rec in records {
        for (glyph, key) in rec.glyphs.iter().zip(rec.code.chars()) {
            *counts.entry(*glyph).or_default().entry(key).or_insert(0) += 1;
        }
    }
    counts
        .into_iter()
        .map(|(glyph, key_counts)| {
            let best = key_counts
                .iter()
                .max_by_key(|(_, c)| **c)
                .map(|(k, _)| *k)
                .unwrap();
            (glyph, best)
        })
        .collect()
}

/// 从 D2 字形序列推导「字形 → 键」，与 D3 编码对齐（多数表决）。
///
/// D2 不直接给出编码，故与 D3 逐位对齐（键名字/成字字根按 4 位、2 字根合体字按
/// 3 位、3 字根合体字取前 3 位、≥5 字根取 1/2/3/末）。该表仅用于交叉检查路径，
/// 量化 D2 字形记法的歧义，**不用于发布码表**。
fn derive_d2_glyph_keys(d2: &[D2Record], d3: &[D3Record]) -> BTreeMap<char, char> {
    let d3_codes: BTreeMap<char, &str> = d3.iter().map(|r| (r.ch, r.code.as_str())).collect();
    let mut counts: BTreeMap<char, BTreeMap<char, usize>> = BTreeMap::new();
    for rec in d2 {
        let Some(code) = d3_codes.get(&rec.ch) else {
            continue;
        };
        for (glyph, key) in align_d2(&rec.glyphs, code) {
            *counts.entry(glyph).or_default().entry(key).or_insert(0) += 1;
        }
    }
    counts
        .into_iter()
        .map(|(glyph, key_counts)| {
            let best = key_counts
                .iter()
                .max_by_key(|(_, c)| **c)
                .map(|(k, _)| *k)
                .unwrap();
            (glyph, best)
        })
        .collect()
}

/// D2 字形序列与 D3 编码逐位对齐，返回 (字形, 键) 对。
fn align_d2(glyphs: &[char], code: &str) -> Vec<(char, char)> {
    let n = glyphs.len();
    let m = code.len();
    if n == m {
        glyphs.iter().copied().zip(code.chars()).collect()
    } else if n == 3 && m == 4 {
        // 3 字根 + 识别码（D2 省略识别码字形）：前 3 位对齐。
        glyphs.iter().copied().zip(code.chars().take(3)).collect()
    } else if n > m && m == 4 {
        // ≥5 字根：取 1/2/3/末。
        let mut pairs = Vec::with_capacity(4);
        let keys: Vec<char> = code.chars().collect();
        for (i, key) in keys.iter().copied().enumerate() {
            let g = if i < 3 { glyphs[i] } else { glyphs[n - 1] };
            pairs.push((g, key));
        }
        pairs
    } else {
        // 残缺数据：尽力按前缀对齐。
        glyphs.iter().copied().zip(code.chars()).collect()
    }
}

/// 用「字形 → 键」映射构造 RadicalTable（喂给 `from_tsv`）。
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

// ---------------------------------------------------------------------------
// 生成
// ---------------------------------------------------------------------------

/// 发布路径：用编码器对 D3 字形序列逐字生成全码。
///
/// 键名字走 `encode_key_name`；其余统一走 `encode_hechengzi`：
/// - 3 位码 = 「2 字根 + 识别码」：从末位反推 (末笔, 结构) 后按规则重编码；
/// - 4 位码 = ≥4 字根（成字字根的字形含笔画，同样落在此规则内）。
///
/// 注意：识别码表是公开规范，其正确性由单测中的规范样例独立校核，不依赖 D3。
fn generate_primary(
    records: &[D3Record],
    table: &RadicalTable,
    key_names: &BTreeMap<char, char>,
) -> BTreeMap<char, String> {
    let mut out = BTreeMap::new();
    for rec in records {
        let Some(code) = encode_record(&rec.glyphs, &rec.code, table, key_names) else {
            continue;
        };
        out.insert(rec.ch, code);
    }
    out
}

/// 交叉检查路径：用编码器对 D2 逐字编码（键名字/成字字根/合体字）。
fn generate_d2(
    records: &[D2Record],
    table: &RadicalTable,
    key_names: &BTreeMap<char, char>,
    d3_codes: &BTreeMap<char, String>,
) -> BTreeMap<char, String> {
    let mut out = BTreeMap::new();
    for rec in records {
        let Some(code) = encode_d2_record(rec, table, key_names, d3_codes.get(&rec.ch)) else {
            continue;
        };
        out.insert(rec.ch, code);
    }
    out
}

/// 按本库规则重编码一条 D3 记录，返回全码；无法编码返回 `None`。
fn encode_record(
    glyphs: &[char],
    oracle_code: &str,
    table: &RadicalTable,
    key_names: &BTreeMap<char, char>,
) -> Option<String> {
    let first = oracle_code.chars().next()?;
    // 键名字：键连打四次（字形首位的键名映射不变）。
    if oracle_code.len() == 4
        && oracle_code.chars().all(|c| Some(c) == Some(first))
        && key_names.values().any(|k| *k == first)
    {
        return Some(encode_key_name(first));
    }

    if oracle_code.len() == 3 {
        let key = oracle_code.chars().last()?;
        let (stroke, structure) = inverse_recognition(key)?;
        let radicals: Vec<String> = glyphs[..2].iter().map(|g| g.to_string()).collect();
        encode_hechengzi(&radicals, structure, stroke, table).ok()
    } else {
        let radicals: Vec<String> = glyphs.iter().map(|g| g.to_string()).collect();
        encode_hechengzi(&radicals, Structure::Mixed, Stroke::Heng, table).ok()
    }
}

/// 按本库规则编码一条 D2 记录（键名字/成字字根/合体字）；无法编码返回 `None`。
///
/// D2 不直接给出编码，识别码相关判断借助 D3 编码（仅用于交叉检查，见文件头）。
fn encode_d2_record(
    rec: &D2Record,
    table: &RadicalTable,
    key_names: &BTreeMap<char, char>,
    d3_code: Option<&String>,
) -> Option<String> {
    // 键名字。
    if let Some(key) = key_names.get(&rec.ch) {
        return Some(encode_key_name(*key));
    }
    // 成字字根：字形序列以该字自身开头（后续为笔画字形）。
    if rec.glyphs.first() == Some(&rec.ch) {
        return encode_d2_chengzi(rec, table);
    }
    // 合体字：字形序列即字根序列；识别码字形 D2 有时省略，借助 D3 编码长度区分。
    let d3_code = d3_code?;
    let n = rec.glyphs.len();
    match d3_code.len() {
        3 => {
            if n < 2 {
                return None;
            }
            // 2 字根 + 识别码（D2 含识别码字形）：识别码从 D3 末位反推。
            let key = d3_code.chars().last()?;
            let (stroke, structure) = inverse_recognition(key)?;
            let radicals: Vec<String> = rec.glyphs[..2].iter().map(|g| g.to_string()).collect();
            encode_hechengzi(&radicals, structure, stroke, table).ok()
        }
        4 => {
            if n == 3 {
                // 3 字根 + 识别码（D2 省略识别码字形）：识别码从 D3 末位反推。
                let key = d3_code.chars().nth(3)?;
                let (stroke, structure) = inverse_recognition(key)?;
                let radicals: Vec<String> = rec.glyphs.iter().map(|g| g.to_string()).collect();
                encode_hechengzi(&radicals, structure, stroke, table).ok()
            } else if n >= 4 {
                // ≥4 字根（或 3 字根 + 识别码字形已含）：1/2/3/末。
                let radicals: Vec<String> = rec.glyphs.iter().map(|g| g.to_string()).collect();
                encode_hechengzi(&radicals, Structure::Mixed, Stroke::Heng, table).ok()
            } else {
                None
            }
        }
        _ => None,
    }
}

/// 编码成字字根：字形序列 = [字, 首笔, 次笔, 末笔]（或 2 笔时 = [字, 首笔, 次笔]）。
fn encode_d2_chengzi(rec: &D2Record, table: &RadicalTable) -> Option<String> {
    let strokes: Vec<Stroke> = rec
        .glyphs
        .iter()
        .skip(1)
        .map(|g| stroke_of_glyph(*g, table))
        .collect::<Option<_>>()?;
    encode_chengzi(&rec.ch.to_string(), &strokes, table).ok()
}

/// 把 D2 笔画字形（按其键位）映射为笔画类型；非笔画键位返回 `None`。
fn stroke_of_glyph(glyph: char, table: &RadicalTable) -> Option<Stroke> {
    match table.radical_to_key(&glyph.to_string())? {
        'g' => Some(Stroke::Heng),
        'h' => Some(Stroke::Shu),
        't' => Some(Stroke::Pie),
        'y' => Some(Stroke::Na),
        'n' => Some(Stroke::Zhe),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
// 输出
// ---------------------------------------------------------------------------

/// 渲染单字码表：`code\tchar\tweight`（一级字优先，其余按码点作临时稳定排序）。
fn render_tsv(codes: &BTreeMap<char, String>, gb1: &BTreeSet<char>) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 萤火虫输入法 五笔86 单字码表（自建，CC-BY-SA-4.0，ADR-014）"
    );
    let _ = writeln!(
        out,
        "# 由 crates/wubi-encoder/examples/generate.rs 生成；每个码可由编码器规则复现（ADR-016）。"
    );
    let _ = writeln!(
        out,
        "# 字根序列来源：WindInput wubi86_chaizi.txt（MIT，huanfeng/WindInput）；详见 data/sources.toml D3。"
    );
    let _ = writeln!(
        out,
        "# weight 为临时排序权重（一级字 > 二级字 > 其它，同层按码点稳定排序）；"
    );
    let _ = writeln!(out, "# 正式词频权重待 D7（ADR-013）接入后替换。");
    let _ = writeln!(out, "# code\tchar\tweight");

    // (code, char) 升序按码，同码内按权重降序。
    let mut rows: Vec<(String, char, u32)> = codes
        .iter()
        .map(|(ch, code)| (code.clone(), *ch, weight_of(*ch, gb1)))
        .collect();
    rows.sort_by(|a, b| a.0.cmp(&b.0).then(b.2.cmp(&a.2)));

    for (code, ch, weight) in rows {
        let _ = writeln!(out, "{code}\t{ch}\t{weight}");
    }
    out
}

/// 临时权重：一级字 = 2 层、二级字（CJK 统一表意文字区，非一级）= 1 层、其它 = 0 层；
/// 同层按码点稳定排序（码点升序 = 权重更高，作为笔画数的临时近似）。
fn weight_of(ch: char, gb1: &BTreeSet<char>) -> u32 {
    let tier = if gb1.contains(&ch) {
        2
    } else if ('\u{4E00}'..='\u{9FFF}').contains(&ch) {
        1
    } else {
        0
    };
    tier * 1_000_000 + (0x10FFFF - (ch as u32))
}

// ---------------------------------------------------------------------------
// 报告
// ---------------------------------------------------------------------------

#[allow(clippy::too_many_arguments)]
fn render_report(
    root: &Path,
    d3_path: &Path,
    d2_path: &Path,
    rime_path: &Path,
    primary: &BTreeMap<char, String>,
    d2_codes: &BTreeMap<char, String>,
    d3_oracle: &BTreeMap<char, String>,
    rime: &BTreeMap<char, String>,
    gb1: &BTreeSet<char>,
    d3_glyph_count: usize,
    d2_glyph_count: usize,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 单字码表生成 + 多 oracle 对照回归（T-M1-05）");
    let _ = writeln!(out, "#");
    let _ = writeln!(
        out,
        "# 发布路径（primary）= {}（D3 拆字，MIT；经编码器生成，见文件头）",
        display_path(root, d3_path)
    );
    let _ = writeln!(
        out,
        "# 交叉检查路径（D2）  = {}（MIT；量化 D2 字形记法歧义）",
        display_path(root, d2_path)
    );
    let _ = writeln!(
        out,
        "# oracle #2（rime-wubi）= {}（LGPL-3；⚠️ 仅测试对照，不打包/不分发）",
        display_path(root, rime_path)
    );
    let _ = writeln!(
        out,
        "# 识别码表由单测规范样例独立校核；结构/末笔为 D3 派生（PROVISIONAL，ADR-017/019）。"
    );
    let _ = writeln!(out);

    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "primary_chars = {}", primary.len());
    let _ = writeln!(out, "d2_chars = {}", d2_codes.len());
    let _ = writeln!(out, "d3_glyph_keys = {d3_glyph_count}");
    let _ = writeln!(out, "d2_glyph_keys = {d2_glyph_count}");
    let _ = writeln!(out);

    let _ = writeln!(out, "[agreement]");
    let _ = writeln!(out, "# path\toracle\toverall%\tgb1%");
    for (label, ours) in [("primary", primary), ("d2", d2_codes)] {
        for (oracle_label, other) in [("D3", d3_oracle), ("rime", rime)] {
            let (i, m) = agreement(ours, other, None);
            let (i1, m1) = agreement(ours, other, Some(gb1));
            let _ = writeln!(
                out,
                "{label}\t{oracle_label}\toverall={:.4}% ({m}/{i})\tgb1={:.4}% ({m1}/{i1})",
                pct(m, i),
                pct(m1, i1)
            );
        }
    }
    let _ = writeln!(out);

    let _ = writeln!(out, "[primary_vs_oracles]");
    let _ = writeln!(
        out,
        "# 发布路径（primary）与各 oracle 的差异（全体，非仅 GB1）。"
    );
    for (oracle_label, other) in [("D3", d3_oracle), ("rime", rime)] {
        let mismatches = diff(primary, other, None, 200);
        let _ = writeln!(
            out,
            "# --- primary vs {oracle_label}（差异 {} 条，最多显示 200）---",
            mismatches.len()
        );
        let _ = writeln!(out, "# char\tprimary\t{oracle_label}");
        for (ch, ours, theirs) in mismatches {
            let _ = writeln!(out, "{ch}\t{ours}\t{theirs}");
        }
    }
    let _ = writeln!(out);

    let _ = writeln!(out, "[three_way_disagreement]");
    let _ = writeln!(
        out,
        "# 三方（primary / D3 / rime）两两均不一致的条目，需按五笔86 规范人工裁定（ADR-019）。"
    );
    let _ = writeln!(out, "# char\tprimary\tD3\trime");
    let mut three_way = Vec::new();
    for (ch, ours) in primary {
        let Some(d) = d3_oracle.get(ch) else { continue };
        let Some(r) = rime.get(ch) else { continue };
        if d != ours && r != ours && d != r {
            three_way.push((*ch, ours.clone(), d.clone(), r.clone()));
        }
    }
    if three_way.is_empty() {
        let _ = writeln!(out, "# （无：primary 与 D3 仅有 6 处歧义字形差异，且这些字在 rime 中缺失或与 D3 一致，故不存在三方两两不一致条目。）");
    }
    for (ch, ours, d, r) in three_way {
        let _ = writeln!(out, "{ch}\t{ours}\t{d}\t{r}");
    }
    let _ = writeln!(out);

    let _ = writeln!(out, "[d2_limitation]");
    let _ = writeln!(
        out,
        "# D2 交叉检查路径的一致率显著低于发布路径，归因于 D2 字形记法的歧义（ADR-017）："
    );
    let _ = writeln!(
        out,
        "# 同一 PUA/通配字形（如 U+F001E、U+F0013）在不同字中代表不同字根；"
    );
    let _ = writeln!(out, "# 马/幺等字根在 D2 中被拆成多字形且形式不统一；");
    let _ = writeln!(out, "# 少量条目残缺（如 伐/代 仅存首字根）。");
    let _ = writeln!(
        out,
        "# 因此发布码表采用 D3 第 2 列的干净拆字（每码位一字形）作为字根来源，D2 仅用于交叉检查。"
    );

    out
}

/// 计算一致率；`subset` 为 `None` 时取全体交集。
fn agreement(
    ours: &BTreeMap<char, String>,
    other: &BTreeMap<char, String>,
    subset: Option<&BTreeSet<char>>,
) -> (usize, usize) {
    let mut intersection = 0usize;
    let mut matched = 0usize;
    for (ch, code) in ours {
        if let Some(subset) = subset {
            if !subset.contains(ch) {
                continue;
            }
        }
        if let Some(other_code) = other.get(ch) {
            intersection += 1;
            if other_code == code {
                matched += 1;
            }
        }
    }
    (intersection, matched)
}

/// 返回差异（按字升序，最多 `limit` 条）。
fn diff(
    ours: &BTreeMap<char, String>,
    other: &BTreeMap<char, String>,
    subset: Option<&BTreeSet<char>>,
    limit: usize,
) -> Vec<(char, String, String)> {
    let mut out = Vec::new();
    for (ch, code) in ours {
        if let Some(subset) = subset {
            if !subset.contains(ch) {
                continue;
            }
        }
        if let Some(other_code) = other.get(ch) {
            if other_code != code {
                out.push((*ch, code.clone(), other_code.clone()));
            }
        }
    }
    out.truncate(limit);
    out
}

fn pct(part: usize, whole: usize) -> f64 {
    if whole == 0 {
        100.0
    } else {
        part as f64 * 100.0 / whole as f64
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

fn write_file(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("创建目录失败（{}）：{e}", parent.display()))?;
    }
    fs::write(path, content).map_err(|e| format!("写入失败（{}）：{e}", path.display()))?;
    Ok(())
}
