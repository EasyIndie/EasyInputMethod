//! 五笔86 验证 oracle #2（rime/rime-wubi）解析器（T-M1-04b）。
//!
//! 把 Rime 字典 `wubi86.dict.yaml` 转成「字\t码」单字表，供 T-M1-05 做多源对照。
//! 按 **ADR-016 / ADR-019**：第三方码表**仅作验证 oracle，不进入发布产物、不打包分发**。
//!
//! 处理规则：
//!   - 只保留 `text` 恰为 1 个字符的条目；
//!   - 同一字多条码时取**最长码（全码）**，长度相同取字典序最小；
//!   - 丢弃含 `z`（Rime 通配/反查）等非 `a`–`y` 的非法五笔码（记数）；
//!   - 输出按字排序的 `字\t码` 表（带 `#` 注释头），并生成统计报告。
//!
//! 先运行 `./data/sources/fetch-wubi-oracle2.sh` 下载源数据（不入库）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example oracle2
//! 可选位置参数覆盖路径：`... -- <rime-yaml> <d3> <gb1> <tsv-out> <report-out>`。

use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

/// 抽样核对：与 D3/规范一致的五笔86 全码。
const SAMPLES: &[(&str, &str)] = &[
    ("的", "rqyy"),
    ("一", "ggll"),
    ("你", "wqiy"),
    ("中", "khk"),
    ("好", "vbg"),
];

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let rime_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/rime-wubi86.dict.yaml"));
    let d3_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/sources/windinput-wubi86-chaizi.txt"));
    let gb1_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/gb2312-level1.txt"));
    let tsv_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-oracle2-single.tsv"));
    let report_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-oracle2-report.txt"));

    let rime_text = fs::read_to_string(&rime_path)
        .map_err(|e| format!("读取 Rime 字典失败（{}）：{e}", rime_path.display()))?;
    let d3_text = fs::read_to_string(&d3_path)
        .map_err(|e| format!("读取 D3 失败（{}）：{e}", d3_path.display()))?;
    let gb1_text = fs::read_to_string(&gb1_path)
        .map_err(|e| format!("读取 GB2312 一级字表失败（{}）：{e}", gb1_path.display()))?;

    let (all_single, stats) = parse_rime(&rime_text)?;
    let d3 = parse_d3(&d3_text)?;
    let gb1: BTreeSet<char> = gb1_text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .filter_map(|l| l.chars().next())
        .collect();

    // 丢弃含 z / 非 a–y 的非法五笔码（Rime 通配、反查等）。
    let mut valid: BTreeMap<char, String> = BTreeMap::new();
    let mut dropped = 0usize;
    for (ch, code) in all_single {
        if code.chars().all(|c| ('a'..='y').contains(&c)) {
            valid.insert(ch, code);
        } else {
            dropped += 1;
        }
    }

    check_samples(&valid)?;

    let overall = agreement(&valid, &d3, None);
    let gb1_rate = agreement(&valid, &d3, Some(&gb1));

    let report = render_report(&ReportData {
        stats: &stats,
        dropped,
        written: valid.len(),
        d3_chars: d3.len(),
        overall,
        gb1: gb1_rate,
        rime_label: &display_path(&root, &rime_path),
        d3_label: &display_path(&root, &d3_path),
    });
    write_file(&tsv_path, &render_tsv(&valid))?;
    write_file(&report_path, &report)?;

    print!("{report}");
    println!("→ 已写入 {}（{} 字）", tsv_path.display(), valid.len());
    Ok(())
}

/// 解析统计。
#[derive(Default)]
struct RimeStats {
    /// 数据区（`...` 之后）非注释、含码的条目数（单字 + 词组）。
    data_entries: usize,
    /// 其中 `text` 恰为 1 个字符的条目数。
    single_entries: usize,
    /// 去重后的唯一单字数（丢弃非法码之前）。
    unique_single: usize,
}

/// 仓库根目录（`crates/wubi-encoder` 的上两级）。
fn workspace_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .unwrap_or_else(|_| PathBuf::from(env!("CARGO_MANIFEST_DIR")))
}

/// 报告里用相对仓库根目录的路径，保证跨机器输出一致。
fn display_path(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .display()
        .to_string()
}

/// 解析 Rime 字典：跳过头部（`...` 之前），只取单字条目并保留最长码。
fn parse_rime(input: &str) -> Result<(BTreeMap<char, String>, RimeStats), Box<dyn Error>> {
    let mut map: BTreeMap<char, String> = BTreeMap::new();
    let mut stats = RimeStats::default();
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
        if code.is_empty() {
            continue;
        }
        stats.data_entries += 1;

        let mut chars = text.chars();
        let ch = match chars.next() {
            Some(c) => c,
            None => continue,
        };
        if chars.next().is_some() {
            continue; // 非单字（词组）
        }
        stats.single_entries += 1;

        let replace = match map.get(&ch) {
            None => true,
            Some(old) => code.len() > old.len() || (code.len() == old.len() && code < old.as_str()),
        };
        if replace {
            map.insert(ch, code.to_string());
        }
    }

    if !in_body {
        return Err("Rime 字典缺少 YAML 文档结束标记 `...`".into());
    }
    stats.unique_single = map.len();
    Ok((map, stats))
}

/// 解析 D3（`字\t字根序列\t五笔码`）为 `字 → 五笔码`。
fn parse_d3(input: &str) -> Result<BTreeMap<char, String>, Box<dyn Error>> {
    let mut map = BTreeMap::new();
    for raw in input.lines() {
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let ch_field = fields.next().unwrap_or_default();
        let _glyphs = fields.next();
        let code = match fields.next() {
            Some(c) => c.trim(),
            None => continue,
        };
        if code.is_empty() {
            continue;
        }
        let mut chars = ch_field.chars();
        if let Some(ch) = chars.next() {
            if chars.next().is_none() {
                map.insert(ch, code.to_string());
            }
        }
    }
    Ok(map)
}

/// 计算一致率；`subset` 为 `None` 时取全体交集。
fn agreement(
    ours: &BTreeMap<char, String>,
    d3: &BTreeMap<char, String>,
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
        if let Some(other) = d3.get(ch) {
            intersection += 1;
            if other == code {
                matched += 1;
            }
        }
    }
    (intersection, matched)
}

/// 抽样核对；任一不符即报错（防止上游数据/解析静默回归）。
fn check_samples(map: &BTreeMap<char, String>) -> Result<(), Box<dyn Error>> {
    for (ch, expected) in SAMPLES {
        let Some(ch) = ch.chars().next() else {
            continue;
        };
        match map.get(&ch) {
            Some(actual) if actual == expected => {}
            Some(actual) => {
                return Err(format!("抽样核对失败：{ch} 期望 {expected}，实际 {actual}").into());
            }
            None => {
                return Err(format!("抽样核对失败：{ch} 不在 oracle #2 单字表中").into());
            }
        }
    }
    Ok(())
}

fn percent(matched: usize, total: usize) -> String {
    if total == 0 {
        "n/a".to_string()
    } else {
        format!("{:.4}%", 100.0 * matched as f64 / total as f64)
    }
}

/// `render_report` 的输入（打包以减少参数个数）。
struct ReportData<'a> {
    stats: &'a RimeStats,
    dropped: usize,
    written: usize,
    d3_chars: usize,
    overall: (usize, usize),
    gb1: (usize, usize),
    rime_label: &'a str,
    d3_label: &'a str,
}

fn render_report(data: &ReportData<'_>) -> String {
    let ReportData {
        stats,
        dropped,
        written,
        d3_chars,
        overall,
        gb1,
        rime_label,
        d3_label,
    } = *data;
    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 验证 oracle #2 报告（T-M1-04b）");
    let _ = writeln!(out, "#");
    let _ = writeln!(
        out,
        "# oracle = {rime_label}（rime/rime-wubi，LGPL-3.0；⚠️ 仅验证对照，不发布/不打包）"
    );
    let _ = writeln!(out, "# 对照   = {d3_label}（D3，MIT）");
    let _ = writeln!(out, "# GB1    = data/generated/gb2312-level1.txt");
    let _ = writeln!(
        out,
        "# 处理：仅单字；同字多码取最长码（并列取最小）；丢弃含 z/非 a–y 的非法码。"
    );
    let _ = writeln!(out);
    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "rime_data_entries = {}", stats.data_entries);
    let _ = writeln!(out, "rime_single_entries = {}", stats.single_entries);
    let _ = writeln!(out, "single_unique_chars = {}", stats.unique_single);
    let _ = writeln!(out, "dropped_invalid_code = {dropped}");
    let _ = writeln!(out, "written_chars = {written}");
    let _ = writeln!(out, "d3_chars = {d3_chars}");
    let _ = writeln!(out, "overall_intersection = {}", overall.0);
    let _ = writeln!(out, "overall_matched = {}", overall.1);
    let _ = writeln!(out, "overall_agreement = {}", percent(overall.1, overall.0));
    let _ = writeln!(out, "gb2312_level1_intersection = {}", gb1.0);
    let _ = writeln!(out, "gb2312_level1_matched = {}", gb1.1);
    let _ = writeln!(out, "gb2312_level1_agreement = {}", percent(gb1.1, gb1.0));
    let _ = writeln!(out);
    let _ = writeln!(out, "[samples]");
    let _ = writeln!(out, "# char\trime\texpected");
    for (ch, code) in SAMPLES {
        let _ = writeln!(out, "{ch}\t{code}\t{code}");
    }
    out
}

/// 渲染可提交的单字表（带溯源注释头，注释行以 `#` 开头）。
fn render_tsv(map: &BTreeMap<char, String>) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 验证 oracle #2 单字表（T-M1-04b）");
    let _ = writeln!(
        out,
        "# 来源：rime/rime-wubi wubi86.dict.yaml（LGPL-3.0）；⚠️ 仅验证对照，不进入发布产物（ADR-016/ADR-019）。"
    );
    let _ = writeln!(
        out,
        "# 处理：仅单字；同字多码取最长码（并列取最小）；丢弃含 z/非 a–y 的非法码。"
    );
    let _ = writeln!(out, "# char\tcode");
    for (ch, code) in map {
        let _ = writeln!(out, "{ch}\t{code}");
    }
    out
}

fn write_file(path: &Path, contents: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|e| format!("创建目录失败（{}）：{e}", parent.display()))?;
    }
    fs::write(path, contents).map_err(|e| format!("写入失败（{}）：{e}", path.display()))?;
    Ok(())
}
