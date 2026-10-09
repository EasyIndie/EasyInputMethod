//! 组合缓冲区长输入复现/基准（MVP-07，见 ADR-062）。
//!
//! 在真实数据上测量「持续输入字母」时单键耗时随组合长度增长的情况。
//!
//! 用法：
//!   cargo run --release -p ime-cli --example compose_bound -- data/generated
//!   /usr/bin/time -l cargo run --release -p ime-cli --example compose_bound -- data/generated   # 另看峰值 RSS

use std::time::Instant;

use ime_core::{EngineOptions, InputMode, Session};
use ime_pinyin::{PinyinEngine, TablePinyinBackend};
use ime_table::{CodeTableEngine, Table};

fn build(data_dir: &str) -> Session {
    let wubi = Table::from_tsv(
        &std::fs::read_to_string(format!("{data_dir}/wubi86-core.tsv")).expect("read wubi86-core"),
    )
    .expect("parse wubi86-core");
    let chars =
        std::fs::read_to_string(format!("{data_dir}/pinyin-chars.tsv")).expect("read pinyin-chars");
    let words =
        std::fs::read_to_string(format!("{data_dir}/pinyin-core.tsv")).expect("read pinyin-core");
    let pinyin =
        TablePinyinBackend::from_tsv(&chars, &words, "compose-bound").expect("parse pinyin");
    let mut session = Session::new(InputMode::Mixed);
    session.configure_engines(&EngineOptions {
        auto_commit: false,
        fuzzy: false,
        z_wildcard: false,
    });
    session.set_wubi_engine(Box::new(CodeTableEngine::new(wubi, 4)));
    session.set_pinyin_engine(Box::new(PinyinEngine::new(Box::new(pinyin), 32)));
    session
}

fn main() {
    let data_dir = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "data/generated".to_string());
    let targets: Vec<usize> = std::env::args()
        .nth(2)
        .map(|s| s.split(',').filter_map(|x| x.parse().ok()).collect())
        .unwrap_or_else(|| vec![8, 16, 32, 64, 128]);
    println!("# compose-bound reproduction (data={data_dir})");
    println!(
        "{:<10} {:>6} {:>12} {:>12} {:>6}",
        "pattern", "len", "total_ms", "worst_ms", "buf"
    );
    for (label, pattern) in [("a", "a"), ("nihao", "nihao"), ("zhongguo", "zhongguo")] {
        for &target in &targets {
            let mut session = build(&data_dir);
            let mut worst = 0.0_f64;
            let start = Instant::now();
            for i in 0..target {
                let ch = pattern.as_bytes()[i % pattern.len()] as char;
                let key_start = Instant::now();
                let _ = session.handle_key(ch);
                worst = worst.max(key_start.elapsed().as_secs_f64() * 1e3);
            }
            let total = start.elapsed().as_secs_f64() * 1e3;
            println!(
                "{label:<10} {target:>6} {total:>12.1} {worst:>12.2} {:>6}",
                session.buffer().len()
            );
        }
    }
}
