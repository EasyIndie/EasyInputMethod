# 252 — B2 批：教学运行时资源（3,000 字，96 B/字）

- 日期：2026-11-06　｜　批次：B2（数据地基）　｜　决策：ADR-311
- 结论：**体积问题解决了**——预渲染后 3,000 字只要 **287,310 字节**，预算 512 KiB 反而有余量。

## 1. 问题

ADR-309 的门槛是"3,000 字、运行资源 ≤512 KiB"。按 B0.json 现状 **558 B/字** 外推要 1.6 MiB，**超三倍**。
实测确认：`--limit 3000` 的 B0.json = **1,619,884 字节**。

## 2. 做法（ADR-311）

改成**预渲染 TSV**：`字 \t 全码 \t 质量 \t 讲解`，宿主只查表展示，不拼句子。

| 方案 | 3,000 字体积 | 说明 |
|---|---|---|
| B0.json（结构化） | 1,619,884 B（540 B/字） | 供构建/查询，不进包 |
| **B0-runtime.tsv（预渲染）** | **287,310 B（96 B/字）** | **预算的 56%**，余量 224 KiB |

压缩来源：① 去掉 `ids`/`positionMismatch`/`frequency`/`notes` 数组/简码/读音等中间字段；
② `partial` 的原因文案从整段 notes 改成短句（"部分字根字形未识别""字根数与码长不符"）。

## 3. 覆盖（3,000 字）

| 质量 | 条数 | 占比 |
|---|---|---|
| `full` | 2,010 | 67.0% |
| `partial` | 770 | 25.7% |
| `unknown` | 220 | 7.3% |

> 1,000 高频字里 `full` 是 73.5%，扩到 3,000 后降到 67.0%——后 2,000 字更生僻、拆字数据更差，属预期。
> `unknown` 从 8 条涨到 220 条（缺全码/缺拆字），如实保留，不猜。

## 4. 一致性

讲解文案由**构建期同一套规则**生成，与 `tools/b0_query.py` 对齐：
`full` 完整讲（编码/字根/识别码依据/简码）、`partial` 必带「拆解待核验」、`unknown` 只说"暂无编码/拆解资料"。

## 5. 验证

- 新增 `platforms/macos/tests/test-b0-runtime.py`：体积 ≤512 KiB、四列、字唯一、无 PUA、
  质量取值合法、`partial` 必带「拆解待核验」、`unknown` 含"暂无"。
- 登记 `data/sources.toml` 的 derived `b0-runtime`（source_ids: D1/D2/D5/D10/D17/D17-bis/D19，SHA-256 固定）。
- `make verify` PASS、离线回归 **61 文件 / 327 例 PASS**。

## 6. 还没做（属 B3）

- 宿主装载（bundle 内 `Contents/Resources/B0-runtime.tsv`）与候选窗提示 UI；
- 装机后的净增量/查询延迟/内存三张实测表（要等候选包）。

## 7. 复现

```sh
python3 modules/hanzi-structure/tools/build_b0.py \
  --codes data/generated/wubi86-single.tsv --radicals data/sources/wubi-lex-86.txt \
  --pua-map modules/hanzi-structure/corpus/pua-map.json \
  --readable-keys data/learning/wubi86-readable-keys.tsv --ids data/sources/ids_lv1.txt \
  --short1 data/sources/wubi86-level1-codes.tsv --short2 data/sources/wubi86-level2-codes.tsv \
  --pinyin data/generated/pinyin-chars.tsv --limit 3000 \
  --out-dir /tmp/b0-3k --runtime-out data/generated/B0-runtime.tsv
```
