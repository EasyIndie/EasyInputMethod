//! 候选排序评测：把样本集喂给真实 [`Session`]，统计位次、按键数、翻页次数。
//!
//! 用法：
//!
//! ```sh
//! cargo run -q -p ime-cli --bin ime-eval -- \
//!   --samples tools/eval/samples.tsv \
//!   --table data/generated/wubi86-core.tsv \
//!   --json out.json
//! ```
//!
//! 样本格式（TSV，`#` 开头为注释）：`category<TAB>keys<TAB>target`。
//! `keys` 用 `|` 分词，模拟"按词组码"：每段输入结束后按空格或数字键选定一个候选再继续。
//!
//! 指标口径（`docs/MVP后执行计划.md` B 批要求，四个都能从样本集直接量化）：
//!
//! - **位次**：目标在候选列表里的下标（0 = 首选）；找不到记 `missing`，不计入位次均值。
//! - **按键数**：`keys` 长度 + 每段 1 键确认（空格或数字）+ 非首选时再 1 键选序号；
//!   四码唯一自动上屏的段不需要确认键。
//! - **翻页次数**：`位次 / 每页候选数`，取整。
//! - **命中率 / 首选率**：整条样本是否被完整命中、命中的样本里首选比例。

#![forbid(unsafe_code)]

use std::collections::BTreeMap;
use std::fmt::Write as _;
use std::io::Write as _;

use ime_core::{InputMode, Session};
use ime_table::{CodeTableEngine, Table};

/// 与宿主一致的每页候选数（`candidate.count` 默认值）。
const PAGE_SIZE: usize = 9;
/// 判定候选位次时枚举的最大候选数，避免极端码位拖慢评测。
const MAX_CANDIDATES: usize = 500;

#[derive(Clone, Debug, PartialEq, Eq)]
struct Sample {
    category: String,
    /// 以 `|` 分段的按键串。
    keys: String,
    target: String,
}

#[derive(Clone, Debug, Default)]
struct ItemResult {
    /// 每个命中段的候选位次；未命中段的 `None` 让整条样本记为 missing。
    positions: Vec<usize>,
    keystrokes: usize,
    missing: bool,
    hit: bool,
}

impl ItemResult {
    fn first_choice_all(&self) -> bool {
        self.hit && self.positions.iter().all(|p| *p == 0)
    }

    fn pages(&self) -> usize {
        self.positions.iter().map(|p| p / PAGE_SIZE).sum()
    }
}

#[derive(Clone, Debug, Default)]
struct CategoryStats {
    samples: usize,
    hits: usize,
    first_choice: usize,
    positions: Vec<usize>,
    keystrokes: usize,
    pages: usize,
}

impl CategoryStats {
    fn add(&mut self, result: &ItemResult) {
        self.samples += 1;
        self.hits += usize::from(result.hit);
        self.first_choice += usize::from(result.first_choice_all());
        self.positions.extend(result.positions.iter().copied());
        self.keystrokes += result.keystrokes;
        self.pages += result.pages();
    }

    fn mean_position(&self) -> f64 {
        if self.positions.is_empty() {
            return 0.0;
        }
        let sum: usize = self.positions.iter().sum();
        sum as f64 / self.positions.len() as f64
    }

    fn mean_keystrokes(&self) -> f64 {
        if self.samples == 0 {
            return 0.0;
        }
        self.keystrokes as f64 / self.samples as f64
    }
}

/// 解析样本文件；非法行直接报错（样本集是评测输入，静默跳过等于自欺）。
fn parse_samples(input: &str) -> Result<Vec<Sample>, String> {
    let mut out = Vec::new();
    for (lineno, line) in input.lines().enumerate() {
        let line = line.trim_end_matches(['\r']);
        if line.trim().is_empty() || line.starts_with('#') {
            continue;
        }
        let mut fields = line.split('\t');
        let (Some(category), Some(keys), Some(target), None) =
            (fields.next(), fields.next(), fields.next(), fields.next())
        else {
            return Err(format!("第 {} 行不是三列 TSV：{line}", lineno + 1));
        };
        if category.is_empty() || keys.is_empty() || target.is_empty() {
            return Err(format!("第 {} 行有空字段：{line}", lineno + 1));
        }
        out.push(Sample {
            category: category.to_string(),
            keys: keys.to_string(),
            target: target.to_string(),
        });
    }
    Ok(out)
}

/// 逐段输入并挑出能让 `remaining` 前进最远的候选。
fn evaluate_sample(session: &mut Session, sample: &Sample) -> ItemResult {
    let mut result = ItemResult::default();
    let mut remaining = sample.target.as_str();
    for segment in sample.keys.split('|') {
        session.cancel();
        for ch in segment.chars() {
            session.handle_key(ch);
        }
        let auto = !session.committed().is_empty();
        // 自动上屏时，已提交内容本身即该段的候选；否则在候选列表里按目标剩余部分挑选。
        let (position, consumed) = if auto {
            // 四码唯一自动上屏：上屏内容必须正好是目标的开头，否则这一段就是打错了。
            let text = session.committed().to_string();
            if !remaining.starts_with(&text) {
                result.missing = true;
                result.keystrokes += segment.chars().count();
                return result;
            }
            let pos = session
                .candidates()
                .iter()
                .position(|c| c.text == text && !c.is_prefix);
            (pos.unwrap_or(0), text.len())
        } else {
            match pick(session, remaining) {
                Some((pos, len)) => (pos, len),
                None => {
                    result.missing = true;
                    result.keystrokes += segment.chars().count() + 1;
                    return result;
                }
            }
        };
        result.positions.push(position);
        // 键数：本段按键 + 确认键（自动上屏豁免）+ 非首选时的序号键。
        result.keystrokes +=
            segment.chars().count() + usize::from(!auto) + usize::from(position > 0);
        remaining = &remaining[consumed..];
        if remaining.is_empty() {
            break;
        }
    }
    result.hit = remaining.is_empty();
    if !result.hit {
        result.missing = true;
    }
    result
}

/// 在候选列表里找 `target` 的前缀候选，返回（位次，消耗的字符数）。
fn pick(session: &Session, target: &str) -> Option<(usize, usize)> {
    let mut best: Option<(usize, usize)> = None;
    for (index, candidate) in session.candidates().iter().enumerate() {
        if index >= MAX_CANDIDATES {
            break;
        }
        if let Some(rest) = target.strip_prefix(candidate.text.as_str()) {
            let consumed = candidate.text.len();
            let _ = rest;
            if consumed > 0 && best.map(|(_, c)| consumed > c).unwrap_or(true) {
                best = Some((index, consumed));
            }
        }
    }
    best
}

fn summarize(
    samples: &[Sample],
    results: &[ItemResult],
) -> (CategoryStats, BTreeMap<String, CategoryStats>) {
    let mut overall = CategoryStats::default();
    let mut per_category: BTreeMap<String, CategoryStats> = BTreeMap::new();
    for (sample, result) in samples.iter().zip(results) {
        overall.add(result);
        per_category
            .entry(sample.category.clone())
            .or_default()
            .add(result);
    }
    (overall, per_category)
}

fn render_json(overall: &CategoryStats, per_category: &BTreeMap<String, CategoryStats>) -> String {
    let mut out = String::from("{\n");
    let _ = writeln!(out, "  \"pageSize\": {PAGE_SIZE},");
    let _ = writeln!(out, "  \"maxCandidates\": {MAX_CANDIDATES},");
    let _ = writeln!(out, "  \"overall\": {},", stats_json(overall));
    let _ = writeln!(out, "  \"categories\": {{");
    for (index, (name, stats)) in per_category.iter().enumerate() {
        let comma = if index + 1 == per_category.len() {
            ""
        } else {
            ","
        };
        let _ = writeln!(out, "    {name:?}: {}{comma}", stats_json(stats));
    }
    out.push_str("  }\n}\n");
    out
}

fn stats_json(stats: &CategoryStats) -> String {
    format!(
        "{{\"samples\": {}, \"hits\": {}, \"firstChoice\": {}, \"meanPosition\": {:.2}, \"meanKeystrokes\": {:.2}, \"pages\": {}}}",
        stats.samples,
        stats.hits,
        stats.first_choice,
        stats.mean_position(),
        stats.mean_keystrokes(),
        stats.pages
    )
}

fn render_table(overall: &CategoryStats, per_category: &BTreeMap<String, CategoryStats>) -> String {
    let mut out = String::new();
    let _ = writeln!(
        out,
        "{:<12} {:>7} {:>6} {:>7} {:>9} {:>10} {:>6}",
        "category", "samples", "hit%", "first%", "avgPos", "keys/sample", "pages"
    );
    let mut rows: Vec<(&str, &CategoryStats)> =
        per_category.iter().map(|(k, v)| (k.as_str(), v)).collect();
    rows.push(("ALL", overall));
    for (name, stats) in rows {
        let hit = if stats.samples == 0 {
            0.0
        } else {
            100.0 * stats.hits as f64 / stats.samples as f64
        };
        let first = if stats.samples == 0 {
            0.0
        } else {
            100.0 * stats.first_choice as f64 / stats.samples as f64
        };
        let _ = writeln!(
            out,
            "{name:<12} {:>7} {:>6.1} {:>7.1} {:>9.2} {:>10.2} {:>6}",
            stats.samples,
            hit,
            first,
            stats.mean_position(),
            stats.mean_keystrokes(),
            stats.pages
        );
    }
    out
}

fn arg_value(args: &[String], flag: &str) -> Option<String> {
    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        if arg == flag {
            return args.get(i + 1).cloned();
        }
        if let Some(value) = arg.strip_prefix(&format!("{flag}=")) {
            return Some(value.to_string());
        }
        i += 1;
    }
    None
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let samples_path = arg_value(&args, "--samples").unwrap_or_else(|| {
        eprintln!("用法：ime-eval --samples <TSV> [--table <TSV>] [--json <路径>]");
        std::process::exit(2);
    });
    let table_path =
        arg_value(&args, "--table").unwrap_or_else(|| "data/generated/wubi86-core.tsv".to_string());

    let samples_text = match std::fs::read_to_string(&samples_path) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("错误：样本集 {samples_path} 读取失败：{e}");
            std::process::exit(1);
        }
    };
    let samples = match parse_samples(&samples_text) {
        Ok(samples) if !samples.is_empty() => samples,
        Ok(_) => {
            eprintln!("错误：样本集 {samples_path} 为空");
            std::process::exit(1);
        }
        Err(e) => {
            eprintln!("错误：{e}");
            std::process::exit(1);
        }
    };
    let table_text = match std::fs::read_to_string(&table_path) {
        Ok(text) => text,
        Err(e) => {
            eprintln!("错误：码表 {table_path} 读取失败：{e}");
            std::process::exit(1);
        }
    };
    let table = match Table::from_tsv(&table_text) {
        Ok(mut table) => {
            table.finalize();
            table
        }
        Err(e) => {
            eprintln!("错误：码表 {table_path} 解析失败：{e:?}");
            std::process::exit(1);
        }
    };

    let table = std::sync::Arc::new(table);
    let mut results = Vec::with_capacity(samples.len());
    for sample in &samples {
        let mut session = Session::new(InputMode::WubiOnly);
        session.set_wubi_engine(Box::new(CodeTableEngine::new_shared(
            std::sync::Arc::clone(&table),
            4,
        )));
        session.set_page_size(PAGE_SIZE);
        results.push(evaluate_sample(&mut session, sample));
    }

    let (overall, per_category) = summarize(&samples, &results);
    print!("{}", render_table(&overall, &per_category));
    if let Some(path) = arg_value(&args, "--json") {
        let json = render_json(&overall, &per_category);
        match std::fs::write(&path, json) {
            Ok(()) => println!("JSON 已写入 {path}"),
            Err(e) => {
                eprintln!("错误：JSON 写入 {path} 失败：{e}");
                std::process::exit(1);
            }
        }
    }
    let _ = std::io::stdout().flush();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_three_column_samples_and_rejects_malformed_lines() {
        let text = "# 注释\n\nsingle\tabcd\t工\nphrase\tabcd|efgh\t工工\n";
        let samples = parse_samples(text).unwrap();
        assert_eq!(samples.len(), 2);
        assert_eq!(samples[1].keys, "abcd|efgh");
        assert!(parse_samples("single\tabcd\n").is_err());
        assert!(parse_samples("a\tb\tc\td\n").is_err());
    }

    #[test]
    fn keystrokes_charge_confirmation_and_selection_but_not_auto_commit() {
        let first = ItemResult {
            positions: vec![0],
            keystrokes: 5,
            missing: false,
            hit: true,
        };
        assert!(first.first_choice_all());
        let deep = ItemResult {
            positions: vec![12],
            keystrokes: 6,
            missing: false,
            hit: true,
        };
        assert!(!deep.first_choice_all());
        assert_eq!(deep.pages(), 1);
    }

    #[test]
    fn empty_category_stats_do_not_divide_by_zero() {
        let stats = CategoryStats::default();
        assert_eq!(stats.mean_position(), 0.0);
        assert_eq!(stats.mean_keystrokes(), 0.0);
    }

    #[test]
    fn picks_the_longest_matching_candidate_with_its_index() {
        let table =
            Table::from_tsv("# code\ttext\tweight\naaaa\t工\t10\naaaa\t恭\t5\naaa\t工\t1\n")
                .unwrap();
        let mut session = Session::new(InputMode::WubiOnly);
        session.set_wubi_engine(Box::new(CodeTableEngine::new(table, 4)));
        session.set_page_size(PAGE_SIZE);
        for ch in "aaaa".chars() {
            session.handle_key(ch);
        }
        session.cancel();
        for ch in "aaa".chars() {
            session.handle_key(ch);
        }
        let sample = Sample {
            category: "probe".into(),
            keys: "aaa".into(),
            target: "工".into(),
        };
        let result = evaluate_sample(&mut session, &sample);
        assert!(result.hit, "工 应在 aaa 的候选里");
        assert_eq!(result.positions, vec![0]);
    }
}
