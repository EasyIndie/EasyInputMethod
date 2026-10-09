//! 启动/建表成本测量（MVP-13 证据）。
//!
//! 用法：
//!   cargo run --release -p ime-cli --example startup_cost -- data/generated

use std::sync::Arc;
use std::time::Instant;

use ime_core::{InputMode, Session};
use ime_pinyin::{PinyinBackend, PinyinEngine, TablePinyinBackend};
use ime_table::{CodeTableEngine, Table};

fn main() {
    let dir = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "data/generated".to_string());
    let wubi_str = std::fs::read_to_string(format!("{dir}/wubi86-core.tsv")).unwrap();
    let chars = std::fs::read_to_string(format!("{dir}/pinyin-chars.tsv")).unwrap();
    let words = std::fs::read_to_string(format!("{dir}/pinyin-core.tsv")).unwrap();

    let start = Instant::now();
    let wubi = Table::from_tsv(&wubi_str).unwrap();
    println!(
        "wubi_table_build_ms={:.1} codes={}",
        start.elapsed().as_secs_f64() * 1e3,
        wubi.len()
    );

    let start = Instant::now();
    let backend: Arc<dyn PinyinBackend> =
        Arc::new(TablePinyinBackend::from_tsv(&chars, &words, "startup").unwrap());
    println!(
        "pinyin_backend_build_ms={:.1}",
        start.elapsed().as_secs_f64() * 1e3
    );

    let wubi = Arc::new(wubi);
    let start = Instant::now();
    let mut sessions = Vec::new();
    for _ in 0..5 {
        let mut session = Session::new(InputMode::Mixed);
        session.set_wubi_engine(Box::new(CodeTableEngine::new_shared(Arc::clone(&wubi), 4)));
        session.set_pinyin_engine(Box::new(PinyinEngine::new_shared(Arc::clone(&backend), 32)));
        sessions.push(session);
    }
    println!(
        "five_sessions_ms={:.3}",
        start.elapsed().as_secs_f64() * 1e3
    );
    println!("sessions={}", sessions.len());
}
