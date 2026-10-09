// 用户词库 TSV 解析器（`ime-dict::parse`）的有界 fuzz 目标。
//
// 有界：超过上限的输入直接跳过，避免 fuzz 诱导无界分配（用户词库本身还有 2 MiB / 10k 条上限）。
#![no_main]

use libfuzzer_sys::fuzz_target;

const MAX_LEN: usize = 256 * 1024;

fuzz_target!(|data: &[u8]| {
    if data.len() > MAX_LEN {
        return;
    }
    if let Ok(text) = std::str::from_utf8(data) {
        let _ = ime_dict::parse(text);
    }
});
