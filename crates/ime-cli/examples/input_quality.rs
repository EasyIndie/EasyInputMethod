//! Reproducible system-dictionary quality and engine timing comparison.
//! Usage: input_quality <core-directory> <reference-directory> <corpus>.
use ime_core::{EngineOptions, InputMode, KeyOutcome, Session};
use ime_pinyin::{PinyinEngine, TablePinyinBackend};
use ime_table::{CodeTableEngine, Table};
use std::{collections::BTreeMap, error::Error, fs, path::Path, time::Instant};

fn reference(path: &Path) -> Result<BTreeMap<String, Vec<String>>, Box<dyn Error>> {
    let mut map: BTreeMap<String, Vec<String>> = BTreeMap::new();
    for line in fs::read_to_string(path)?
        .lines()
        .filter(|l| !l.starts_with('#'))
    {
        let fields: Vec<_> = line.split('\t').collect();
        if fields.len() == 3 {
            map.entry(fields[1].into())
                .or_default()
                .push(fields[0].into());
        }
    }
    Ok(map)
}
fn main() -> Result<(), Box<dyn Error>> {
    let args: Vec<_> = std::env::args().collect();
    if args.len() != 4 {
        return Err("参数：核心目录 参考目录 验收集".into());
    }
    let core = Path::new(&args[1]);
    let reference_dir = Path::new(&args[2]);
    let start = Instant::now();
    let table = Table::from_tsv(&fs::read_to_string(core.join("wubi86-core.tsv"))?)?;
    let backend = TablePinyinBackend::from_tsv(
        &fs::read_to_string(reference_dir.join("pinyin-chars.tsv"))?,
        &fs::read_to_string(core.join("pinyin-core.tsv"))?,
        "quality",
    )?;
    let mut session = Session::new(InputMode::WubiOnly);
    session.set_wubi_engine(Box::new(CodeTableEngine::new(table, 4)));
    session.set_pinyin_engine(Box::new(PinyinEngine::new(Box::new(backend), 32)));
    session.configure_engines(&EngineOptions {
        auto_commit: false,
        fuzzy: true,
        z_wildcard: false,
    });
    eprintln!("load_ms={:.3}", start.elapsed().as_secs_f64() * 1000.0);
    // Measure resident memory before allocating full reference dictionaries.
    #[cfg(target_os = "macos")]
    {
        let output = std::process::Command::new("ps")
            .args(["-o", "rss=", "-p", &std::process::id().to_string()])
            .output()?;
        eprintln!(
            "loaded_process_rss_kib={}",
            String::from_utf8_lossy(&output.stdout).trim()
        );
    }
    let wubi = reference(&reference_dir.join("wubi86-phrases.tsv"))?;
    let pinyin = reference(&reference_dir.join("pinyin-words.tsv"))?;
    let mut timings = Vec::new();
    println!("mode\tcategory\tsplit\ttext\tinput\trank\tkey_cost");
    for (mode, name, dictionary) in [
        (InputMode::WubiOnly, "wubi", &wubi),
        (InputMode::PinyinOnly, "pinyin", &pinyin),
    ] {
        session.set_mode(mode);
        for line in fs::read_to_string(&args[3])?
            .lines()
            .filter(|l| !l.starts_with('#'))
        {
            let fields: Vec<_> = line.split('\t').collect();
            if fields.len() != 3 {
                return Err("验收集列数错误".into());
            }
            let (category, split, text) = (fields[0], fields[1], fields[2]);
            let mut best: Option<(usize, usize, String)> = None;
            let spellings: std::collections::BTreeSet<String> = dictionary
                .get(text)
                .into_iter()
                .flatten()
                .flat_map(|spelling| {
                    if mode == InputMode::PinyinOnly {
                        vec![spelling.replace(' ', ""), spelling.replace(' ', "'")]
                    } else {
                        vec![spelling.clone()]
                    }
                })
                .collect();
            for input in spellings {
                session.cancel();
                for key in input.chars() {
                    let start = Instant::now();
                    let outcome = session.handle_key(key);
                    timings.push(start.elapsed().as_secs_f64() * 1000.0);
                    if outcome != KeyOutcome::Consumed {
                        return Err(format!("非预期自动提交：{input}").into());
                    }
                }
                for page in 0..session.page_count() {
                    let index = session.candidates().iter().position(|c| c.text == text);
                    if let Some(index) = index {
                        let rank = page * 9 + index + 1;
                        let cost = input.chars().count() + page + 1;
                        if session.handle_key(char::from(b'1' + index as u8))
                            != KeyOutcome::Committed(text.into())
                        {
                            return Err(format!("显示与数字提交不一致：{input}/{text}").into());
                        }
                        if best
                            .as_ref()
                            .is_none_or(|old| (cost, rank) < (old.0, old.1))
                        {
                            best = Some((cost, rank, input.clone()));
                        }
                        break;
                    }
                    session.page(1);
                }
            }
            if let Some((cost, rank, input)) = best {
                println!("{name}\t{category}\t{split}\t{text}\t{input}\t{rank}\t{cost}");
            } else {
                println!("{name}\t{category}\t{split}\t{text}\t\t0\t0");
            }
        }
    }
    timings.sort_by(f64::total_cmp);
    if !timings.is_empty() {
        eprintln!(
            "keys={} key_p50_ms={:.6} key_p95_ms={:.6} key_max_ms={:.6}",
            timings.len(),
            timings[timings.len() / 2],
            timings[(timings.len() * 95).div_ceil(100) - 1],
            timings[timings.len() - 1]
        );
    }
    Ok(())
}
