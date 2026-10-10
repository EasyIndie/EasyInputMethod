//! 用户词库**学习落盘**成本基准（T-MVP-07）。
//!
//! 用法：cargo run --release -p ime-dict --example learn_cost -- [N]
//! 输出每次 `learn` 的平均/最坏耗时与文件大小（当前实现每次学习全量原子写）。

use std::time::Instant;

use ime_dict::Store;

fn main() {
    let n: usize = std::env::args()
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(2000);
    let dir = std::env::temp_dir().join(format!("lampyris-learn-cost-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let path = dir.join("user-dictionary.tsv");
    let mut store = Store::load(&path).unwrap();

    let mut worst = 0.0_f64;
    let start = Instant::now();
    for i in 0..n {
        let t = Instant::now();
        store
            .learn("wubi", "ab", &format!("词{i}"))
            .expect("learn 应成功");
        worst = worst.max(t.elapsed().as_secs_f64() * 1e3);
    }
    let total = start.elapsed().as_secs_f64() * 1e3;
    let kib = std::fs::metadata(&path)
        .map(|m| m.len() / 1024)
        .unwrap_or(0);
    println!(
        "learns={n} total_ms={total:.1} avg_ms={:.2} worst_ms={worst:.2} file_kib={kib}",
        total / n as f64
    );
    std::fs::remove_dir_all(&dir).ok();
}
