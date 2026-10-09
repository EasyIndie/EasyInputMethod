// 拼音 TSV 解析器（`ime-pinyin::TablePinyinBackend::from_tsv`）的有界 fuzz 目标。
//
// 同一份输入同时充当字表与词表，覆盖两条解析分支。
#![no_main]

use libfuzzer_sys::fuzz_target;

const MAX_LEN: usize = 256 * 1024;

fuzz_target!(|data: &[u8]| {
    if data.len() > MAX_LEN {
        return;
    }
    if let Ok(text) = std::str::from_utf8(data) {
        let _ = ime_pinyin::TablePinyinBackend::from_tsv(text, text, "fuzz");
    }
});
