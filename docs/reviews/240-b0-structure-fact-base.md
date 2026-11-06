# 240 — B0 结构事实库试点：1,000 高频字，76% 可完整解释

- 日期：2026-11-06　｜　决策：ADR-308　｜　模块：`modules/hanzi-structure/`
- 关联：ADR-189（模块边界）、报告 239（三级简码暂缓 → 识别码解释更重要）

## 1. 做了什么

按 ADR-189 的边界，在 `modules/hanzi-structure/` 落地第一版**派生**事实库：

| 文件 | 作用 |
|---|---|
| `spec/B0-schema.md` | schema v1 + 三类判定规则 + 质量分级 + PUA 禁令 |
| `tools/build_b0.py` | 生成器：**输入输出全部显式传参**，不假设主仓库路径 |
| `corpus/B0.json` | 1,000 高频字的事实（363 KB，人可读 JSON） |
| `corpus/B0-report.json` | 覆盖统计 + 输入文件 SHA-256 + 生成命令 |
| `tests/validate_b0.py` | 独立复核：按输入**重算**并逐条比对 |
| `provenance/B0.md` | 来源/许可/SHA/复现命令/已知缺口 |
| `platforms/macos/tests/test-hanzi-structure-b0.py` | 把它接入离线回归 |

数据全部来自**已登记来源**：D1（全码）、D2（可读拆字，MIT）、D17/D17-bis（简码，自编 CC-BY-SA-4.0）、
D5/D10（读音/字频，MIT）。**没有引入任何新数据源**。

## 2. 覆盖（1,000 高频字）

| 质量 | 数量 | 说明 |
|---|---|---|
| `full` | **760（76%）** | 三类判定成功；其中 **513 条**给出识别码依据（末笔 × 结构 ⇒ 字母） |
| `partial` | 232 | 字根数与码长对不上（D2 拆字省略/多算），已写 `notes` |
| `unknown` | 8 | 缺全码或缺拆字数据 |

分类：合体字 725、成字字根 42、键名字 23（其余 8 条 unknown）。

识别码解释是**可直接给用户看的**，例如：

```json
{"char": "和", "code": "tkg",
 "components": ["禾", "口"],
 "recognition": {"key": "g", "stroke": "横", "structure": "左右",
                 "because": "2 个字根不足四码：末笔横 + 结构左右 ⇒ 识别码 g"}}
```

## 3. 为什么值得做

报告 239 的结论是"三级简码按键收益只有 −0.22，其真实价值是少记识别码"。
B0 正是把这个"少记"变成可解释：**76% 的高频字能说出识别码从哪来**，而这是靠**派生**得到的，
不是逐字手写（对比：现有学习区只有 104 条完整解释）。

## 4. 已知缺口（如实记录）

1. **232 条 partial**：D2 拆字与全码的"字根数"对不上。要修不是靠猜，需要**PUA 解码 / 字根身份**（ADR-189 的 corpus 阶段）。
   本轮试过用 PUA 出现频率反推"识别码字形"，前 9 个 PUA 的一致性 ≥99%，但整体只有 18/89 唯一 → **不做不可验证的推断**。
2. **笔画/笔顺、字根图形、几何资源**不在 B0（`assets` 阶段）。
3. **体积**：363 KB / 1,000 字（可读 JSON，含缩进）。若将来做运行包，需按 ADR-189 的"资源分层"设计紧凑格式与按需加载，
   不能把全量可读 JSON 塞进安装包。
4. B0 **不接产品**：不进输入热路径、不改候选排序、不进安装包；接入（候选窗拆解提示）属 L3，需另做 ADR/性能评估。

## 5. 下一步

> 后续：PUA 解码尝试见 **报告 241**（学出 184 个映射，但没能救回 partial，且发现 v1 的 BMP PUA 校验漏洞）。


| 序 | 事项 | 依据 |
|---|---|---|
| 1 | **PUA/字根身份解码** → 把 partial 232 条救回来 | 本报告 §4.1 |
| 2 | 扩到 3,000–5,000 高频字并做紧凑格式（体积/加载实测） | ADR-189「体积与内存」 |
| 3 | L3：候选窗显示"末笔+结构⇒识别码"与"简码等级"（只读、可关） | 研究文档 §4.4 |
| 4 | L4：练习题库由 B0 生成（错因分类：错根/错识别码/多打一码） | 研究文档 §4.5 |

## 6. 复现

```sh
cd modules/hanzi-structure
python3 tools/build_b0.py --codes ../../data/generated/wubi86-single.tsv \
  --radicals ../../data/sources/wubi-lex-86.txt \
  --short1 ../../data/sources/wubi86-level1-codes.tsv \
  --short2 ../../data/sources/wubi86-level2-codes.tsv \
  --pinyin ../../data/generated/pinyin-chars.tsv --limit 1000 --out-dir corpus
python3 tests/validate_b0.py --corpus corpus/B0.json --report corpus/B0-report.json \
  --codes ../../data/generated/wubi86-single.tsv --radicals ../../data/sources/wubi-lex-86.txt \
  --short1 ../../data/sources/wubi86-level1-codes.tsv \
  --short2 ../../data/sources/wubi86-level2-codes.tsv --pinyin ../../data/generated/pinyin-chars.tsv
```
