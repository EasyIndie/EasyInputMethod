# T-ROOT86：五笔86 根序补齐（主体已完成；残余 28 条待认领）

- 状态：**主体完成 + 残余待认领**（2026-11-19）
- 后续工作模型建议：**pro**（残余都是口径判断/生僻部件，无批量红利）
- 前置：ADR-377/378（运行时 v3、字表 5,021）、ADR-380（只做 86）、ADR-382（专利过期、不追授权）、
  ADR-383（R9-bis 成字字根部件尾）、ADR-384（码表勘误 + 假阳性教训）

## 1. 已完成

| 指标 | 起点 | 现在 |
|---|---|---|
| GB2312 一级 3,755 字 `full` | 3,435（91.5%） | **3,755（100.0%）** |
| 学习表 5,021 字 `full` | 4,546 | **4,993（99.4%）** |
| 学习表 `partial` | 475 | **28** |
| 判定表 D25 | 0 行 | **451 行（fix 449 / blocked 2）** |

产出：

- `data/learning/wubi86-root-order.tsv`（D25，451 行，每行带码位—字根—键位与依据）
- `tools/wubi86-root-pilot.py`（分层抽样）、`tools/wubi86-root-infer.py`（受控推断）
- 报告 306（逐批判定）、317（码表审计）、323（外部交叉验证）、324（受控推断与复核）
- 标准增补：LWS-86 的 R1-bis（母拆三段）、R9-bis（成字字根部件尾）；D26 码表勘误机制

## 2. 残余 28 条（不可批量，逐条需外部证据）

| 类型 | 条数 | 代表 | 缺什么 |
|---|---|---|---|
| IDS 只有 1 段 | 5 | 侃 / 彘 / 羁 / 豳 / 盥 | ids_lv1 对生僻字只给一层，需补 IDS 或字形 |
| 生僻部件无拆法证据 | ~10 | 濮·噗·蹼·幞·镤（菐）/ 璺（𦥑）/ 纛（縣） | 这些部件不在 241 条标准字根表，也无可靠样本 |
| IDS 与码表口径冲突 | ~13 | 鲆 / 驿 / 爰 / 驺 / 骧 / 巯 / 遽 / 夔 / 燮 / 辔 / 耜 / 鬯 | IDS 部件与码位字母对不上，需判定哪边错 |

工作方式（已验证有效，勿改）：`python3 tools/wubi86-root-infer.py` 出候选 → 人工逐位复核 →
通过才抄进 D25 → `build_b0.py --root-order` 重跑。**推断结果绝不允许直接进 `full`**（ADR-382 不猜）。

## 3. 已验证不可行的省事路线（不要重复尝试）

- 用 IDS 叶子 + 241 标准字根反推根序：475 条里只有 1 条能复现（ADR-380 结果）——直到 2026-11-19 引入
  **成字字根折叠 + 双读法 + KNOWN_PARTS** 后才成为主力手段（报告 324）；
- cjk-decomp 直接对齐（报告 279 §6：738 条 0 条可确认）；
- 外部拆字表入库：`hantang/search-wubi` 无许可、`sdcb/wubi86-viewer` 含微软专有词库（报告 323）。

## 4. 复跑

```sh
python3 tools/wubi86-root-infer.py                 # 生成候选（build/inference/）
cd modules/hanzi-structure && python3 tools/build_b0.py ... --root-order ../../data/learning/wubi86-root-order.tsv
python3 platforms/macos/tests/test-wubi86-root-order.py
python3 tools/wubi86-std-check.py --bundle build/wubi86-std-1.0 --level L4
```
