use ime_table::Table;
use std::{fs, time::Instant, hint::black_box};
fn main() {
 let input=fs::read_to_string("data/generated/wubi86-core.tsv").unwrap();
 let mut elapsed=Vec::new();
 for _ in 0..20 {
  let start=Instant::now();
  let table=Table::from_tsv(black_box(&input)).unwrap();
  elapsed.push(start.elapsed().as_secs_f64()*1000.0);
  for code in ["wq", "ltif", "gggg", "kwwl", "a", "zzzz"] {
   black_box(table.exact(code));black_box(table.prefix(code, 7));
  }
 }
 let first=elapsed[0];
 let raw=elapsed.clone();
 elapsed.sort_by(|a,b|a.total_cmp(b));
 println!("{{\"samples\":20,\"first_ms\":{},\"raw_ms\":{:?},\"parse_p50_ms\":{},\"parse_p95_ms\":{},\"parse_max_ms\":{}}}",first,raw,elapsed[9],elapsed[18],elapsed[19]);
}
