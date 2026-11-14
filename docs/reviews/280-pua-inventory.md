# 280 — N1-d 补充区 PUA 核验与 B0 接入（ADR-353）

> 2026-11-14。**只核验 D2 的补充区 PUA；不猜字形、不发 PUA、不引入未许可字体。**

## 1. 先更正上一版清单的数据源错误

初版 `pua_inventory.py` 把 **D3**（`data/sources/windinput-wubi86-chaizi.txt`）当成了 D2，
统计出「266 PUA / 156 known / 110 unresolved」。D3 用的是 **BMP PUA（U+E0xx）**，
而 B0 实际使用的 D2（`data/sources/wubi-lex-86.txt`）是 **补充区 PUA（U+F00xx）**；
`pua-map.json` 只覆盖 D3 的 BMP PUA，不能解码 D2 的补充区。上一版数字、报告 280 的样本与
ADR-353 的补充数据均不适用于真实 B0，已全部更正。

## 2. 范围与统计（3,000 字 B0）

| 项 | 数值 |
|---|---|
| D2 补充区 PUA（可逐位定位） | **79** |
| 其中已有 `(PUA, 键位)` 核验 | **66** |
| 清单状态 | **verified 58 / partial 8 / unresolved 13** |
| 出现次数（可定位字根位） | 793 |

产物：

- `modules/hanzi-structure/corpus/pua-supplementary.tsv`：`U+xxxxx\t键\t字根\tverified\t证据`；
- `modules/hanzi-structure/corpus/pua-inventory.tsv`：`pua\tlabel\tstatus\tkeys\toccurrences\tsamples`；
  `unresolved` 的 label 留空。

## 3. 方法（可审计、可复现）

1. **逐位**：D2 第二列是「一个码位一个字形」的连写。`len(glyphs)==len(code)` 时，末位 PUA 是识别码槽，
   丢弃；其余位与 `code[i]` 对齐。`len(glyphs)==len(code)-1` 时识别码字形省略，所有字形都是字根。
   其它长度（多出识别码槽或位次错位）**不计入可定位清单**，避免把识别码槽当字根。
2. **键位约束**：同一个 PUA 在不同码位可能是不同部件（例如 U+F001E 在 G 位是「一」，在 A 位不是）。
   核验表按 `(PUA, 键位)` 收录，而不是只按 PUA；这样不会把「一」错标到 A 位。
3. **身份依据**：D2 的样本字 + 该位码键 + 公开五笔86 字根表；例如 U+F014E 在 年/气/制/牛 的 R 位是「𠂉」，
   U+F007A 在 共/黄/供 的 A 位是「龷」，U+F002F 在 进/讲/界 的 J 位是「刂」。
4. **字形参考**：qingg 仓库的 `98WB-2.otf`（名称表含 **SIL OFL 1.1**，Source Han Sans 派生、已改保留字名）
   仅用于构建期人工比对旧码位的字形；**不随包分发、不复制轮廓**。2024 年 `98WB-3.otf` 无许可记录，未采用；
   D2 新增的 F014x 在参考字体中不对应，身份只由样本字、码位与标准字根表支持。未使用任何未许可五笔字体。
5. **不猜**：只收三点同时成立的条目（样本字、码位键、标准字根表）。其余保持 `unresolved`，
   不用「看起来像」硬填。

## 4. 接入 B0

`build_b0.py` 新增 `--pua-supplementary`，`decode` 对补充区 PUA 先查 `(PUA, 键位)`、再查 `(PUA, '*')`；
末位识别码槽仍按 v4 规则丢弃。同时按 ADR-310 修正：**D3 不再作 `componentsSource`**，只作构建期 oracle。

| 指标 | 接入前 | 接入后 |
|---|---|---|
| B0 语料 1,000 字 `full` | 735 | **919** |
| B0 语料 1,000 字 `partial` | 257 | **73** |
| B0 语料 1,000 字 `unknown` | 8 | 8 |
| 运行时 3,000 字 `full` | 1,904 | **2,454** |
| 运行时 3,000 字 `partial` | 876 | **326** |
| 运行时 3,000 字 `unknown` | 220 | 220 |
| `componentsSource` | D1/D2/D3 | **D1/D2** |
| 运行时体积 | ≈121 KB | 119,472 B（≈40 B/字） |

产物仍**不含任何 PUA**；`test-b0-runtime.py` 的「无私有区 / 字根键位前缀 / 体积」契约通过。

## 5. 仍未解决的 13 个 PUA

| PUA | 键 | 次数 | 样本 | 为什么先不填 |
|---|---|---|---|---|
| U+F005A | q,r | 20 | 昏氏抵低柳聊昂卿 | 同一字形在「氏/氐」与「卯/留/迎/印」间复用，单一身份会误标 |
| U+F0016 | e | 15 | 限丧辱唇眼辰恨根 | 是「艮」的下半，按 E 位直标「艮」会教错键位 |
| U+F0067 | u,g | 14 | 补毒裤裕裙衫袍每 | 点/捺形，可能同时是识别码槽与部件 |
| U+F0064 | r | 11 | 葱汤烫场扬忽吻肠 | 形似「勿」，但 R 位与标准 Q 位不一致 |
| U+F001B | f,h | 8 | 才于宇闭团财乎材 | 同一字形兼「才」与「于/亅」，单一 label 会误标 |
| U+F002A | q,i | 8 | 脊挑率桃姚兆逃函 | 「儿/兆」两读，I/Q 位不统一 |
| U+F0145 | n,x | 4 | 我盛拽成 | 新码位，参考字体不对应；N 位像「乚」、X 位像「匕」 |
| U+F0052 | n,h | 3 | 武鹅心 | 「弋/止」位次错位，标任一都会触发键位不符 |
| U+F0061 | q,n | 3 | 熬万鳌 | 形似「万/力」，Q/N 位不统一 |
| U+F000C | n | 1 | 马 | 多数场合是识别码槽，不应当字根 |
| U+F004A | y | 1 | 瓦 | 形似「瓦」，但 Y 位与 G 位不一致 |
| U+F004F | n | 1 | 藏 | 仅一字，证据不足 |
| U+F0055 | n | 1 | 鼎 | 形似「爿」，仅一字，证据不足 |

这些条目继续以 `？:键` 出现在 `partial` 条目中，符合 ADR-309「宁可不填，也不猜」。

## 6. 关联

- `modules/hanzi-structure/tools/build_b0.py`、`pua_inventory.py`
- `corpus/pua-supplementary.tsv`、`corpus/pua-inventory.tsv`、`corpus/B0.json`、`corpus/B0-report.json`
- `data/generated/B0-runtime.tsv`、`modules/keymap/data/key-roots-wubi86-audit.md`
- ADR-353、ADR-310、`provenance/B0.md`、`docs/数据来源与许可.md`
- 测试：`platforms/macos/tests/test-pua-inventory.py`、`test-b0-runtime.py`、`test-hanzi-structure-b0.py`
