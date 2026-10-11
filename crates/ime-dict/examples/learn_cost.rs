//! 用户词库**学习落盘**成本基准（T-MVP-07 / TD-01）。
//!
//! 用法：cargo run --release -p ime-dict --example learn_cost -- [N]
//! 输出每次 `learn` 的分位数耗时与文件大小（当前实现每次学习原子写整文件）。

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

    let mut samples = Vec::with_capacity(n);
    let mut worst = 0.0_f64;
    let mut worst_at = 0;
    for i in 0..n {
        let t = Instant::now();
        store
            .learn("wubi", "ab", &format!("词{i}"))
            .expect("learn 应成功");
        let ms = t.elapsed().as_secs_f64() * 1e3;
        if ms > worst {
            worst = ms;
            worst_at = i;
        }
        samples.push(ms);
    }
    let total: f64 = samples.iter().sum();
    samples.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let at = |q: f64| samples[((samples.len() - 1) as f64 * q) as usize];
    let kib = std::fs::metadata(&path)
        .map(|m| m.len() / 1024)
        .unwrap_or(0);
    println!(
        "learns={n} avg_ms={:.2} p50_ms={:.2} p95_ms={:.2} p99_ms={:.2} max_ms={:.2}@{} total_ms={total:.1} file_kib={kib}",
        total / n as f64,
        at(0.50),
        at(0.95),
        at(0.99),
        worst,
        worst_at
    );
    std::fs::remove_dir_all(&dir).ok();
}
