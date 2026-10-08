//! 五笔86 拆字数据交叉校验工具（T-M1-04）。
//!
//! 加载两份 MIT「字 → 字根拆分」数据，逐字比对，输出差异报告：
//!   - D2：`data/sources/wubi-lex-86.txt`（aardio/wubi-lex，MIT）
//!   - D3：`data/sources/windinput-wubi86-chaizi.txt`（huanfeng/WindInput，MIT）
//!
//! 先运行 `./data/sources/fetch-wubi-chaizi.sh` 下载源数据（不入库）。
//! 本工具只列事实差异、**不裁定**对错（裁定见 T-M1-05）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example crosscheck
//! 可选位置参数覆盖路径：`... -- <d2> <d3> <out>`。

use std::collections::{BTreeMap, BTreeSet};
use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::path::{Path, PathBuf};

/// 每份数据：字 → 字根序列（每项为单个字根字符）。
type ChaiziMap = BTreeMap<char, Vec<String>>;

/// 差异报告中分歧明细的最大条数（超出只记总数）。
const MAX_DIFF_LINES: usize = 200;

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
    let out_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/chaizi-diff.txt"));

    let d2_text = fs::read_to_string(&d2_path)
        .map_err(|e| format!("读取 D2 失败（{}）：{e}", d2_path.display()))?;
    let d3_text = fs::read_to_string(&d3_path)
        .map_err(|e| format!("读取 D3 失败（{}）：{e}", d3_path.display()))?;

    let d2 = parse_d2(&d2_text)?;
    let d3 = parse_d3(&d3_text)?;

    let report = crosscheck(&d2, &d3);
    let rendered = render_report(
        &report,
        &display_path(&root, &d2_path),
        &display_path(&root, &d3_path),
    );

    write_report(&out_path, &rendered)?;
    print!("{rendered}");
    println!("\n→ 已写入 {}", out_path.display());
    Ok(())
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

/// 取单字符列；为空或多字符即报错。
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

/// 解析 D2（aardio/wubi-lex，格式 `字\t字根1字根2...`，字根逐字符拼接）。
fn parse_d2(input: &str) -> Result<ChaiziMap, Box<dyn Error>> {
    let mut map = ChaiziMap::new();
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
            .ok_or_else(|| format!("D2 第 {lineno} 行缺少制表符：{line}"))?;
        if fields.next().is_some() {
            return Err(format!("D2 第 {lineno} 行字段过多：{line}").into());
        }
        let ch = single_char(ch_field, "D2", lineno)?;
        let radicals: Vec<String> = rad_field.chars().map(|c| c.to_string()).collect();
        if radicals.is_empty() {
            return Err(format!("D2 第 {lineno} 行字根为空：{line}").into());
        }
        map.insert(ch, radicals);
    }
    Ok(map)
}

/// 解析 D3（huanfeng/WindInput，格式 `字\t字根（空格分隔）\t五笔码`）。
fn parse_d3(input: &str) -> Result<ChaiziMap, Box<dyn Error>> {
    let mut map = ChaiziMap::new();
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
            .ok_or_else(|| format!("D3 第 {lineno} 行少于两段：{line}"))?;
        let ch = single_char(ch_field, "D3", lineno)?;
        let radicals: Vec<String> = rad_field.split_whitespace().map(str::to_string).collect();
        if radicals.is_empty() {
            return Err(format!("D3 第 {lineno} 行字根为空：{line}").into());
        }
        map.insert(ch, radicals);
    }
    Ok(map)
}

/// 交叉校验结果。
struct Report {
    intersection: usize,
    only_d2: BTreeSet<char>,
    only_d3: BTreeSet<char>,
    /// 分歧明细（按字符升序）：字 → (D2 字根序列, D3 字根序列)。
    divergences: Vec<(char, Vec<String>, Vec<String>)>,
}

fn crosscheck(d2: &ChaiziMap, d3: &ChaiziMap) -> Report {
    let mut intersection = 0usize;
    let mut only_d2 = BTreeSet::new();
    let mut divergences = Vec::new();

    for (ch, d2_seq) in d2 {
        match d3.get(ch) {
            Some(d3_seq) => {
                intersection += 1;
                if d2_seq != d3_seq {
                    divergences.push((*ch, d2_seq.clone(), d3_seq.clone()));
                }
            }
            None => {
                only_d2.insert(*ch);
            }
        }
    }
    let only_d3 = d3.keys().copied().filter(|c| !d2.contains_key(c)).collect();

    Report {
        intersection,
        only_d2,
        only_d3,
        divergences,
    }
}

/// 把字根序列渲染为可读文本；PUA 字符（字体私有区）转成 `<U+XXXX>` 便于人工裁定。
fn render_sequence(seq: &[String]) -> String {
    let mut out = String::new();
    for token in seq {
        for ch in token.chars() {
            if is_pua(ch) {
                let _ = write!(out, "<U+{:04X}>", ch as u32);
            } else {
                out.push(ch);
            }
        }
    }
    out
}

/// 是否属于 Unicode 私有使用区（BMP PUA 与两个补充平面 PUA）。
fn is_pua(c: char) -> bool {
    let cp = c as u32;
    (0xE000..=0xF8FF).contains(&cp)
        || (0xF_0000..=0xF_FFFD).contains(&cp)
        || (0x10_0000..=0x10_FFFD).contains(&cp)
}

fn render_report(report: &Report, d2_label: &str, d3_label: &str) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 拆字交叉校验差异报告（T-M1-04）");
    let _ = writeln!(out, "#");
    let _ = writeln!(out, "# D2 = {d2_label}");
    let _ = writeln!(out, "# D3 = {d3_label}");
    let _ = writeln!(
        out,
        "# 说明：只列事实差异，不裁定对错（裁定见 T-M1-05）。PUA 字根以 <U+XXXX> 表示。"
    );
    let _ = writeln!(out);
    let _ = writeln!(out, "[summary]");
    let _ = writeln!(out, "intersection = {}", report.intersection);
    let _ = writeln!(out, "only_in_d2 = {}", report.only_d2.len());
    let _ = writeln!(out, "only_in_d3 = {}", report.only_d3.len());
    let _ = writeln!(out, "divergent = {}", report.divergences.len());

    let _ = writeln!(out);
    let _ = writeln!(out, "[divergences]");
    let _ = writeln!(out, "# char\td2_radicals\td3_radicals");
    for (ch, d2_seq, d3_seq) in report.divergences.iter().take(MAX_DIFF_LINES) {
        let _ = writeln!(
            out,
            "{ch}\t{}\t{}",
            render_sequence(d2_seq),
            render_sequence(d3_seq)
        );
    }
    let shown = report.divergences.len().min(MAX_DIFF_LINES);
    let _ = writeln!(
        out,
        "# 共 {} 条分歧，已显示前 {} 条（上限 {MAX_DIFF_LINES}）。",
        report.divergences.len(),
        shown
    );
    out
}

fn write_report(path: &Path, content: &str) -> Result<(), Box<dyn Error>> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = fs::File::create(path)?;
    file.write_all(content.as_bytes())?;
    Ok(())
}
