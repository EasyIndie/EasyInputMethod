# 解析器 fuzz（`lampyris-fuzz`）

对**唯一不可信输入入口**做有界模糊测试：用户词库 TSV、系统码表 TSV、拼音 TSV。见 ADR-061。

> 这是**独立 workspace**（`fuzz/Cargo.toml` 自带 `[workspace]`），不属于主 workspace，
> 不参与 `make verify`、不入发布产物。`libfuzzer-sys` 仅为 dev 依赖。

## 运行

需要 nightly 工具链 + `cargo-fuzz`（见 `make bootstrap`）：

```sh
make fuzz                      # 三个目标各跑 30 秒（默认）
make fuzz FUZZ_SECONDS=120     # 自定义时长
cargo +nightly fuzz run dict_parser   # 单个目标，跑到崩溃/Ctrl-C
```

三个目标：

| 目标 | 被测解析器 |
|---|---|
| `dict_parser` | `ime_dict::parse`（用户词库 TSV v1） |
| `table_parser` | `ime_table::Table::from_tsv`（系统码表 TSV） |
| `pinyin_parser` | `ime_pinyin::TablePinyinBackend::from_tsv`（拼音字表/词表 TSV） |

## 边界语料

“有界”由两部分保证：

1. **目标内长度上限**（256 KiB）——超过即跳过，避免 fuzz 诱导无界分配；
2. **主 workspace 的确定性边界语料单测**（每个 crate 的 `adversarial_corpus_*`）——
   截断行、缺列/多余列、CRLF、BOM、NUL、非 BMP、超范围数字、空字段、超长行等，
   随 `make verify` 每次运行，**不依赖 nightly**。

## 崩溃复现

`cargo fuzz run <target>` 发现崩溃时，输入会写到
`fuzz/artifacts/<target>/`；用 `cargo +nightly fuzz run <target> <该文件>` 复现。
`corpus/`、`artifacts/`、`target/` 均已 gitignore。
