//! 内置样本引擎数据。
//!
//! FFI 会话默认使用极小样本（与 `ime-cli` 的回退表同构），保证 C ABI 可链接、
//! 可冒烟、可单测，无需外部数据文件。真实数据文件的加载路径属 P1-M3 macOS 宿主。

use ime_pinyin::TablePinyinBackend;
use ime_table::Table;

/// 迷你五笔码表（验收样本：`wq`→你、`kwwl`→中华人民共和国）。
pub fn wubi_table() -> Table {
    let entries: &[(&str, &str, i32)] = &[
        ("wq", "你", 100),
        ("wqiy", "你", 100),
        ("trnt", "我", 90),
        ("q", "我", 100),
        ("kwwl", "中华人民共和国", 100),
        ("khyy", "中文", 95),
        ("gggg", "王", 90),
        ("vb", "好", 80),
    ];
    let mut table = Table::new();
    for (code, text, weight) in entries {
        table.insert(code, text, *weight);
    }
    table.finalize();
    table
}

/// 迷你拼音表（验收样本：`nihao`→你好、`zhongwen`→中文）。
pub fn pinyin_backend() -> TablePinyinBackend {
    let chars = "# 音节\t字\tweight\n\
                 wo\t我\t100\n\
                 ni\t你\t90\n\
                 hao\t好\t80\n\
                 zhong\t中\t60\n\
                 wen\t文\t55\n\
                 guo\t国\t50\n\
                 ren\t人\t45\n";
    let words = "# 拼音\t词\tweight\n\
                 ni hao\t你好\t200\n\
                 zhong wen\t中文\t160\n\
                 zhong guo\t中国\t130\n";
    TablePinyinBackend::from_tsv(chars, words, "内置样本拼音").expect("样本拼音表恒可解析")
}
