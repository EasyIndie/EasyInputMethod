# 277 — 整句模型调研与 ADR-352（U3-1）

> 2026-11-14。**只做调研/ADR：未下载语料、未改引擎、未新增数据文件。**

## 结论

- 改判 ADR-299：允许**可选**的整句 bigram 模型，默认 `pinyin.sentence_model=false`；ADR-299 分段拼接仍是默认路径。
- 主选语料：**中文 Wikipedia 2026-11-01 首个分片**，CC BY-SA 4.0，压缩 258,466,938 B、187,712 条，
  SHA1 `a7094e62…`；构建期下载，原始文件不入库。
- 模型：词级 bigram + 词格 Viterbi；原型 `pinyin-bigram.tsv`，记录词表 SHA；内存超支再转可复现二进制。
- 预计：模型 TSV 6–10 MB、常驻 12–20 MiB；p95 增量 <1 ms；可选档门槛 40–48 MiB。
- 实施 M1–M4 约 2 周，需用户批准语料下载与可选档预算后再开工。

## 语料对比（摘要）

| 候选 | 许可 | 规模 | 结论 |
|---|---|---|---|
| 中文 Wikipedia 2026-11-01 分片 1 | CC BY-SA 4.0（已核对） | 258 MB / 187,712 条 | **主选** |
| 项目自编短句 + domain/input-quality | CC-BY-SA-4.0 | < 100 KB | 仅评测，不训练 |
| 中文 Wikinews | CC BY 2.5 | 较小 | 可选补充，本次不用 |
| OpenSubtitles / OPUS | 各子集不同 | 大 | 暂不采用（许可需逐个核） |
| THUCNews | 学术/非商业 | 大 | 不采用（与 GPL-3 冲突） |
| Chinese Gigaword / LDC | 付费 | 大 | 不采用 |
| Common Crawl | 混合页面许可 | 极大 | 不采用（不可审计） |

## 验证

- 本次无代码/数据改动，不需要 `make verify`；README/研究文档已按索引规则更新。
- 语料大小与 SHA 来自 Wikimedia dump 目录的 HEAD/dumpstatus，未下载正文。

## 关联

- 研究全文：`docs/research/sentence-model-corpus.md`
- ADR：`docs/决策记录.md` ADR-352
- 既有实现：ADR-299 多词分段拼接；评估工具 `tools/eval`
