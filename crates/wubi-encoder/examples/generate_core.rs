//! T-M1-09：生成**内置核心码表**（单字全量 + 精选高频词组）。
//!
//! 体积预算（`docs/技术方案.md` §7.2）：内置核心 ≤ 0.8 MB。
//! 裁剪规则（见文件头注释，也写入报告）：
//!   - 单字：`wubi86-single.tsv` **全量保留**（约 313 KB）；
//!   - 词组：按 jieba 真实词频（ADR-013）**全局降序**，取前
//!     [`CORE_PHRASE_LIMIT`] 条，加 D15 训练词及 D16 自编组合词；
//!     新组合由现有编码器生成，权重 1，不改变已有词频（等权按 code、text 升序）。
//!
//! 输入：
//!   - 单字码表：`data/generated/wubi86-single.tsv`（T-M1-05，`code\t字\tweight`）；
//!   - 词组码表：`data/generated/wubi86-phrases.tsv`（T-M1-06b，`code\t词组\tweight`）。
//!
//! 输出：
//!   - `data/generated/wubi86-core.tsv`（单字 + 精选词组，`code\ttext\tweight`）；
//!   - `data/generated/wubi86-core-report.txt`（实测体积 + 裁剪规则 + 验收样本）。
//!
//! 用法（仓库根目录）：
//!   cargo run -p wubi-encoder --example generate_core
//! 可选位置参数覆盖路径：`... -- <单字> <词组> <core 输出> <报告输出>`。

use std::error::Error;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};

/// 内置核心码表的词组上限条数（`docs/技术方案.md` §7.2 的「20k 基础词组加训练词」）。
const CORE_PHRASE_LIMIT: usize = 20_000;

/// 内置核心体积预算（0.8 MB，按 1000 进制保守取值）。
const BUDGET_BYTES: usize = 800_000;

/// 内置核心必须包含的验收样本词组（码写死，见 T-M1-06b / 技术方案 §6.2）。
const REQUIRED_PHRASES: &[(&str, &str)] = &[
    ("输入法", "ltif"),
    ("世界", "anlw"),
    ("人民", "wwna"),
    ("中文", "khyy"),
    ("计算机", "ytsm"),
    ("经济学", "xiip"),
    ("图书馆", "lnqn"),
    ("中华人民共和国", "kwwl"),
];

/// 内置核心必须包含的验收样本单字（码写死）。
const REQUIRED_SINGLES: &[(&str, &str)] = &[("你", "wqiy")];

/// 因词频过低被排除出内置核心的样本（存在于全量词组表，属可选包 1）。
const BELOW_CUTOFF_SAMPLES: &[(&str, &str)] = &[];

struct Row {
    code: String,
    text: String,
    weight: u32,
}

fn main() -> Result<(), Box<dyn Error>> {
    let root = workspace_root();
    let mut args = std::env::args_os().skip(1);
    let single_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-single.tsv"));
    let phrases_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-phrases.tsv"));
    let core_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-core.tsv"));
    let report_path = args
        .next()
        .map(PathBuf::from)
        .unwrap_or_else(|| root.join("data/generated/wubi86-core-report.txt"));

    let single_text = fs::read_to_string(&single_path)
        .map_err(|e| format!("读取单字码表失败（{}）：{e}", single_path.display()))?;
    let phrases_text = fs::read_to_string(&phrases_path)
        .map_err(|e| format!("读取词组码表失败（{}）：{e}", phrases_path.display()))?;

    let singles = parse_rows(&single_text, "单字码表")?;
    let mut phrases = parse_rows(&phrases_text, "词组码表")?;
    if singles.is_empty() {
        return Err("单字码表为空".into());
    }

    let domain = fs::read_to_string(root.join("data/domain-vocabulary.tsv"))?;
    let mut selected = supplement_phrases(&mut phrases, &singles, &domain)?;
    let coverage = fs::read_to_string(root.join("data/input-quality.tsv"))?;
    selected.extend(
        coverage
            .lines()
            .filter(|line| !line.starts_with('#'))
            .filter_map(|line| {
                let fields: Vec<_> = line.split('\t').collect();
                (fields.len() == 3 && fields[1] == "train").then(|| fields[2].to_string())
            }),
    );
    let kept_phrases = top_phrases(&phrases, CORE_PHRASE_LIMIT, &selected);
    verify_required(&singles, &kept_phrases)?;

    let core_tsv = render_core(&singles, &kept_phrases);
    let core_bytes = core_tsv.len();
    if core_bytes > BUDGET_BYTES {
        return Err(
            format!("内置核心超出体积预算：{core_bytes} 字节 > {BUDGET_BYTES} 字节").into(),
        );
    }
    write_file(&core_path, &core_tsv)?;

    let report = render_report(
        &root,
        &single_path,
        &phrases_path,
        &core_path,
        &singles,
        &phrases,
        &kept_phrases,
        core_bytes,
    );
    write_file(&report_path, &report)?;

    print!("{report}");
    println!("\n→ 内置核心码表已写入 {}", core_path.display());
    println!("→ 报告已写入 {}", report_path.display());
    Ok(())
}

/// 解析 `code\ttext\tweight`，忽略注释与空行。
fn parse_rows(input: &str, label: &str) -> Result<Vec<Row>, Box<dyn Error>> {
    let mut rows = Vec::new();
    for (idx, raw) in input.lines().enumerate() {
        let lineno = idx + 1;
        let line = raw.trim_start_matches('\u{feff}').trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let code = fields.next().unwrap_or_default().trim();
        let text = fields.next().unwrap_or_default().trim();
        let weight_field = fields.next().unwrap_or_default().trim();
        if code.is_empty() || text.is_empty() || weight_field.is_empty() {
            return Err(format!("{label} 第 {lineno} 行缺列：{line}").into());
        }
        let weight = weight_field
            .parse::<u32>()
            .map_err(|e| format!("{label} 第 {lineno} 行权重非法：{weight_field}（{e}）"))?;
        rows.push(Row {
            code: code.to_string(),
            text: text.to_string(),
            weight,
        });
    }
    Ok(rows)
}

/// 全局按词频降序取前 `limit` 条（等权按 code、text 升序，可复现）。
fn top_phrases(
    phrases: &[Row],
    limit: usize,
    selected: &std::collections::BTreeSet<String>,
) -> Vec<Row> {
    let mut sorted: Vec<&Row> = phrases.iter().collect();
    sorted.sort_by(|a, b| {
        b.weight
            .cmp(&a.weight)
            .then(a.code.cmp(&b.code))
            .then(a.text.cmp(&b.text))
    });
    sorted
        .into_iter()
        .enumerate()
        .filter(|(index, row)| *index < limit || selected.contains(row.text.as_str()))
        .map(|(_, r)| Row {
            code: r.code.clone(),
            text: r.text.clone(),
            weight: r.weight,
        })
        .collect()
}

/// Add explicitly registered combinations without changing existing frequencies.
fn supplement_phrases(
    phrases: &mut Vec<Row>,
    singles: &[Row],
    source: &str,
) -> Result<std::collections::BTreeSet<String>, Box<dyn Error>> {
    let codes: std::collections::BTreeMap<&str, &str> = singles
        .iter()
        .map(|row| (row.text.as_str(), row.code.as_str()))
        .collect();
    let existing: std::collections::BTreeSet<String> =
        phrases.iter().map(|row| row.text.clone()).collect();
    let mut selected = std::collections::BTreeSet::new();
    for (index, line) in source
        .lines()
        .enumerate()
        .filter(|(_, line)| !line.starts_with('#') && !line.is_empty())
    {
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() != 3
            || fields[1].chars().count() < 2
            || fields[1].chars().count() != fields[2].split_whitespace().count()
            || !selected.insert(fields[1].to_string())
        {
            return Err(format!("D16第{}行格式、字音对齐或重复词错误", index + 1).into());
        }
        let character_codes = fields[1]
            .chars()
            .map(|ch| {
                codes
                    .get(ch.to_string().as_str())
                    .copied()
                    .ok_or_else(|| format!("D16词{}的字{ch}缺少单字全码", fields[1]))
            })
            .collect::<Result<Vec<_>, _>>()?;
        let code = wubi_encoder::encode_phrase(&character_codes)?;
        if !existing.contains(fields[1]) {
            phrases.push(Row {
                code,
                text: fields[1].to_string(),
                weight: 1,
            });
        }
    }
    Ok(selected)
}

/// 断言验收样本在核心表中；码不一致或缺失则报错。
fn verify_required(singles: &[Row], phrases: &[Row]) -> Result<(), Box<dyn Error>> {
    for (text, expected) in REQUIRED_SINGLES {
        match find(singles, text) {
            Some((code, _)) if code == *expected => {}
            Some((code, _)) => {
                return Err(format!("单字 {text} 码应为 {expected}，实际 {code}").into());
            }
            None => return Err(format!("单字样本缺失：{text}").into()),
        }
    }
    for (text, expected) in REQUIRED_PHRASES {
        match find(phrases, text) {
            Some((code, _)) if code == *expected => {}
            Some((code, _)) => {
                return Err(format!("词组 {text} 码应为 {expected}，实际 {code}").into());
            }
            None => return Err(format!("词组样本缺失：{text}（可能被裁剪）").into()),
        }
    }
    Ok(())
}

fn find<'a>(rows: &'a [Row], text: &str) -> Option<(&'a str, u32)> {
    rows.iter()
        .find(|r| r.text == text)
        .map(|r| (r.code.as_str(), r.weight))
}

/// 渲染核心码表：单字 + 精选词组，`code` 升序、同码内 `weight` 降序。
fn render_core(singles: &[Row], phrases: &[Row]) -> String {
    let mut rows: Vec<&Row> = singles.iter().chain(phrases.iter()).collect();
    rows.sort_by(|a, b| {
        a.code
            .cmp(&b.code)
            .then(b.weight.cmp(&a.weight))
            .then(a.text.cmp(&b.text))
    });

    let mut out = String::new();
    let _ = writeln!(
        out,
        "# 萤火虫输入法 五笔86 内置核心码表（自建，CC-BY-SA-4.0，ADR-014）"
    );
    let _ = writeln!(
        out,
        "# 由 crates/wubi-encoder/examples/generate_core.rs 生成（T-M1-09）。"
    );
    let _ = writeln!(
        out,
        "# 裁剪规则：单字全量保留；前 {CORE_PHRASE_LIMIT} 基础词组+D15训练词+D16组合词；已有频次不变，新组合权重1。"
    );
    let _ = writeln!(
        out,
        "# 单字来源：WindInput（MIT，D3）；词组/词频：jieba（MIT，D10）及自编组合词（CC-BY-SA-4.0，D16）。"
    );
    let _ = writeln!(out, "# code\ttext\tweight");
    for row in rows {
        let _ = writeln!(out, "{}\t{}\t{}", row.code, row.text, row.weight);
    }
    out
}

#[allow(clippy::too_many_arguments)]
fn render_report(
    root: &Path,
    single_path: &Path,
    phrases_path: &Path,
    core_path: &Path,
    singles: &[Row],
    phrases: &[Row],
    kept_phrases: &[Row],
    core_bytes: usize,
) -> String {
    let mut out = String::new();
    let _ = writeln!(out, "# 五笔86 内置核心码表报告（T-M1-09）");
    let _ = writeln!(out, "#");
    let _ = writeln!(
        out,
        "# 单字码表：{}（全量）",
        display_path(root, single_path)
    );
    let _ = writeln!(
        out,
        "# 词组码表：{}（裁剪，并补充data/domain-vocabulary.tsv）",
        display_path(root, phrases_path)
    );
    let _ = writeln!(out, "# 输出：{}", display_path(root, core_path));
    let _ = writeln!(out);

    let _ = writeln!(out, "[trim_rule]");
    let _ = writeln!(out, "single_rows = {}（全量保留）", singles.len());
    let _ = writeln!(out, "phrase_rows_full = {}（含D16新组合）", phrases.len());
    let _ = writeln!(
        out,
        "phrase_limit = {CORE_PHRASE_LIMIT}（前 N 基础词+D15训练词+D16组合词；新词权重1，等权按 code/text 升序）"
    );
    let _ = writeln!(out, "phrase_rows_kept = {}", kept_phrases.len());
    let _ = writeln!(out);

    let _ = writeln!(out, "[size]");
    let _ = writeln!(out, "core_rows = {}", singles.len() + kept_phrases.len());
    let _ = writeln!(out, "core_bytes = {core_bytes}");
    let _ = writeln!(out, "budget_bytes = {BUDGET_BYTES}（0.8 MB）");
    let _ = writeln!(
        out,
        "within_budget = {}",
        if core_bytes <= BUDGET_BYTES {
            "yes"
        } else {
            "no"
        }
    );
    let _ = writeln!(out);

    let _ = writeln!(out, "[required_samples]");
    let _ = writeln!(out, "# text\tcode\tweight");
    for (text, _) in REQUIRED_SINGLES {
        let (code, weight) = find(singles, text).expect("verify_required 已检查");
        let _ = writeln!(out, "{text}\t{code}\t{weight}");
    }
    for (text, _) in REQUIRED_PHRASES {
        let (code, weight) = find(kept_phrases, text).expect("verify_required 已检查");
        let _ = writeln!(out, "{text}\t{code}\t{weight}");
    }
    let _ = writeln!(out);

    let _ = writeln!(out, "[below_cutoff]");
    let _ = writeln!(
        out,
        "# 以下样本因词频过低被排除出内置核心（存于全量词组表 / 可选包 1）："
    );
    let _ = writeln!(out, "# text\tcode\tweight");
    for (text, _) in BELOW_CUTOFF_SAMPLES {
        match find(phrases, text) {
            Some((code, weight)) => {
                let _ = writeln!(out, "{text}\t{code}\t{weight}");
            }
            None => {
                let _ = writeln!(out, "{text}\tMISSING\t0");
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn domain_generation_preserves_existing_weights_and_rejects_unencodable_data() {
        let singles = parse_rows("wqiy\t你\t10\nvbg\t好\t9\n", "fixture").unwrap();
        let mut phrases = parse_rows("wqvb\t你好\t123\n", "fixture").unwrap();
        let selected = supplement_phrases(&mut phrases, &singles, "聊天\t你好\tni hao\n").unwrap();
        assert!(selected.contains("你好"));
        assert_eq!(phrases.len(), 1);
        assert_eq!(phrases[0].weight, 123);
        let mut empty = Vec::new();
        supplement_phrases(&mut empty, &singles, "聊天\t你好\tni hao\n").unwrap();
        assert_eq!((empty[0].code.as_str(), empty[0].weight), ("wqvb", 1));
        assert!(supplement_phrases(&mut Vec::new(), &singles, "聊天\t你们\tni men\n").is_err());
        assert!(supplement_phrases(&mut Vec::new(), &singles, "聊天\t你好\tni\n").is_err());
        assert!(supplement_phrases(
            &mut Vec::new(),
            &singles,
            "聊天\t你好\tni hao\n聊天\t你好\tni hao\n"
        )
        .is_err());
    }
}
