# 241 — PUA 字根解码尝试：学出 184 个映射，但没能救回 partial

- 日期：2026-11-06　｜　工具：`modules/hanzi-structure/tools/decode_pua.py`
- 关联：报告 240（B0 试点）、ADR-308、ADR-189（corpus 阶段）

## 1. 目标

报告 240 的 B0 有 **232 条 partial**（字根数与码长对不上）。假设：把 D3（WindInput）里的
**私有区（PUA）字形**解码成可读字根后，组件序列就能对上码长，从而救回这些字。

## 2. 做法（可复现，不含猜测）

D2（aardio/wubi-lex）与 D3 各自给出同一字的字根序列。**逐字对齐**（两源长度一致时）即可学出
`PUA → 可读字根`：

- 对齐成功 **6,191** 字（长度不一致 670 字，跳过）；
- 观测到 **251** 个不同的 PUA 字形、共 19,420 次配对；
- 采纳条件：样本 ≥3 且主导读法占比 ≥90% → **184 个可确认**，67 个标 ambiguous（不猜）。

典型映射：`U+E09B→口`（1058 次）、`U+E001→一`（909）、`U+E10F→人`（501）、`U+E172→氵`（338，唯一）。

## 3. 结果：覆盖没有提升，但发现两个真问题

| 版本 | full | partial | unknown |
|---|---|---|---|
| B0 v1（报告 240，仅 D2） | 760 | 232 | 8 |
| B0 v2（D2 优先 + D3 兜底 + PUA 解码） | **754** | **238** | 8 |

**v1 的 760 里混进了 18 条含 BMP 私有区字形的组件**（如 `在` = `[U+E816, 丨, 土]`）——
v1 的校验器只拦了补充区 PUA（≥U+F0000），漏了 BMP PUA（U+E000–U+F8FF）。
v2 把两种 PUA 都拦下、解不出来就丢弃并降级为 partial，所以 full 从 760 降到 **754**：
这是**修正**，不是退步。

同时 D3 的"字根序列"并不可靠：`是`（jghu）给出 7 个字形、`年`（rhfk）7 个、`以`（nywy）7 个，
里面混着识别码字形与笔画字形。因此采用 D3 反而更差，最终 **D2 优先、D3 仅兜底**（实际采用 D3 的只有 76 条）。

## 4. 结论与建议

1. **PUA 解码本身是可行的**（184/251 可确认，且高样本项一致性 ≥99%），值得作为 corpus 阶段的资产保留；
2. **但它救不了 partial**：问题不在"字根认不出"，而在**两源都不是干净的"字根序列 + 结构"数据集**；
3. B0 v2 保持诚实口径：full 754（76%）、partial 238、unknown 8，**524 条**给出确认依据（识别码 514 条）；
4. 要再往上，需要的是**自建 corpus**（字根字形 ↔ 编码位置的对应、笔画/笔顺），这正是 ADR-189 里尚未启动的部分，
   不是靠现有两源再拼一次能解决的。

**建议**（待决策）：

| 方案 | 代价 | 收益 |
|---|---|---|
| A. 接受 76%，用 partial 降级表述（"这个字的拆解待核验"） | 0 | 立即可用 |
| B. 人工核验 top-500 的 partial（约 120 条） | 半天人工 | 高频字覆盖 →95% |
| C. 启动自建 corpus（字根字形库 + 笔画数据） | 周级 | 覆盖 →100%，并解锁练习/字形图示 |

## 5. 复现

```sh
cd modules/hanzi-structure
python3 tools/decode_pua.py --d2 ../../data/sources/wubi-lex-86.txt \
  --d3 ../../data/sources/windinput-wubi86-chaizi.txt --out corpus/pua-map.json
python3 tools/build_b0.py --codes ../../data/generated/wubi86-single.tsv \
  --radicals ../../data/sources/wubi-lex-86.txt \
  --d3 ../../data/sources/windinput-wubi86-chaizi.txt --pua-map corpus/pua-map.json \
  --short1 ../../data/sources/wubi86-level1-codes.tsv \
  --short2 ../../data/sources/wubi86-level2-codes.tsv \
  --pinyin ../../data/generated/pinyin-chars.tsv --limit 1000 --out-dir corpus
python3 tests/validate_b0.py --corpus corpus/B0.json --report corpus/B0-report.json \
  --codes ../../data/generated/wubi86-single.tsv --radicals ../../data/sources/wubi-lex-86.txt \
  --short1 ../../data/sources/wubi86-level1-codes.tsv \
  --short2 ../../data/sources/wubi86-level2-codes.tsv --pinyin ../../data/generated/pinyin-chars.tsv
```
