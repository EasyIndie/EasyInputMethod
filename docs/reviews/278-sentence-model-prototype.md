# 278 — 整句模型 M1/M2 原型实测（U3-1，未合入）

> 2026-11-14，air。按 ADR-352 做了本地原型：下载中文 Wikipedia 分片、生成 bigram、
> 在 `ime-pinyin` 里加可选词格打分并对照。**结论：当前数据下无可测收益，原型未合入仓库。**
> 工作区已还原，原始 dump 已从 `/tmp` 删除。

## 1. 做了什么（仅本地，未提交）

- 下载 `zhwiki-20261101-pages-articles-multistream1.xml-p1p187712.bz2`（258,466,938 B，SHA1 `a7094e62…`）。
- `tools/prepare-bigram.py`：流式解压 XML → 抽正文 → OpenCC 繁转简 → 用 `pinyin-core.tsv` 最长匹配分词 →
  统计词级 bigram；前 20,000 页得到 625,073 句 / 13,042,856 tokens / 200,000 条 bigram，
  产物 **2.70 MB**（`pinyin-bigram.tsv`）。
- `ime-pinyin` 增加 `BigramModel`（词 ID + count）、`PinyinBackend::compose_sentence`、词格 Viterbi；
  `PinyinEngine` 在整串不是精确词条时追加一条整句候选；默认关闭。
- `ime-cli` 增加 `IME_BIGRAM_PATH` 用于本地对照。

## 2. 实测

| 指标 | 无模型 | 有模型 |
|---|---|---|
| 常驻存活堆（ime-cli release，vmmap） | 13.6 MiB | 18.4 MiB |
| physical footprint | 17.5 MiB | 22.2 MiB |
| 6 条长拼音 convert p95 | 0.037 ms | 0.068 ms |
| 自编 PassageBank 100 句首选完全命中 | **27 / 100** | **27 / 100** |

扩展词表（`pinyin-extended.tsv`）+ 对应模型同样为 27/100，无变化。

## 3. 为什么没有收益

- 语料是百科书面语，缺少「吧/把」这类口语句末虚词的上下文；模型不能凭空学到。
- 主导错误是**分词/词表覆盖**，不是路径打分：
  - `qingbachuanghuguanshang` → `请把窗户观赏`（`关上` 不在核心词表）；
  - `womenyiqiqugongyuansanbu` → `我们一起去公元散布`（`散步` 不在核心词表）；
  - 扩展词表包含 `关上`/`散步` 后，仍受其它未登录词与路径打分影响，首选不变。
- 模型只会在**现有词表路径**里重排；没有的新词/新切分无法被 bigram 修复。
- 追加自编 64 句口语种子（本地实验）后，PassageBank 首选仍是 27/100；种子太小，
  且不能针对未登录词。

## 4. 结论与建议

- 不把该原型合入仓库：默认关闭的模型没有可测收益，只会增加 2.7 MB 数据与核心 ABI 面。
- ADR-352 维持「设计方案」，实现状态回到未开工。
- 若继续 U3-1，建议先把钱花在**词表/分词覆盖**（扩展词表 + 未登录词处理）和
  **许可干净的口语语料**（如逐子集审计 OpenSubtitles）上；在评测集首选率有 ≥5pp 提升前不接模型。
- 评测必须用自编/保留句，且训练语料绝不能包含评测句。

## 5. 证据

本次原型未入库，临时产物已删除；可复现步骤与预算见
`docs/research/sentence-model-corpus.md` 与 ADR-352。
