# 243 — B0 schema v3：占位组件 + 键位推断（附 D3 解析缺陷）

- 日期：2026-11-06　｜　关联：报告 240/241/242、ADR-189/308/309
- 产物：`modules/hanzi-structure/`（`spec/B0-schema.md` v3、`tools/build_b0.py`、`tests/validate_b0.py`、`tools/b0_query.py`）

## 1. 做了什么

报告 242 的 A 类 54 条（丢 PUA 导致"组件数 ↔ 码长"对不上）改为**占位组件**：

- 解不出的 BMP 私有区字形不再丢弃，改记为 `components[i] = null`（**产物仍不含任何 PUA**）；
- 占位仍参与"组件数 ↔ 码长"判定，键位由码位推断：第 i 个组件 ↔ `code[i]`；
- 因此这些字重新得到识别码推导（末笔 × 结构），但按规则**不得判 `full`**——字形毕竟没认出来。

消费契约同步收紧：`partial` 的讲解现在给出 `？(d) 丨(h) 土(f)` 这样的键位序列，
并明确"拆解待核验"，绝不把占位当已知字形。

## 2. 顺手查出一个真缺陷（D3 解析）

`build_b0.py` 用同一个 `load_radicals()` 读 D2 和 D3，但两份格式不同：

| 来源 | 字根列格式 | 原代码 | 后果 |
|---|---|---|---|
| D2 `wubi-lex-86.txt` | 字根**连写**（`亻田一`） | `list(parts[1])` ✅ | — |
| D3 `windinput-wubi86-chaizi.txt` | 字根**空格分隔**（`亻 田 一`） | `list(parts[1])` ❌ | 空格被当成字根，组件里混入 `' '` |

同时 D2 首行有 BOM、D3 用 CRLF，都没清。影响：

- 只要 D3 兜底被选中，组件就会出现 `[' ', ' ']` 这类脏数据（报告 241 时已存在，未被校验器拦住）；
- 部分本可判 `full` 的字被降级。

修复（`load_radicals` 只服务 D2；新增 `load_d3` 用 `split()`，两处都清 BOM/CRLF，`decode_pua.py` 同步）：

| 指标 | 修复前 | 修复后 |
|---|---|---|
| `full` | 753 | **759** |
| `withRecognition` | 514 | **525** |
| 含空白字符的组件 | 存在 | **0**（校验器新增拦截） |

## 3. 当前覆盖（B0，1,000 字，schema v3）

| 指标 | 数值 |
|---|---|
| `full` / `partial` / `unknown` | **759 / 233 / 8** |
| 可解释识别码 | **525** |
| 含占位组件的条目 | **192**（占位组件 380 个） |

233 条 `partial` 按"组件数 − 码长"分类，全部有明确病因：

| 差值 | 数量 | 含义 | 下一步 |
|---|---|---|---|
| `0` | 172 | 字根数与码长相符（四码字），但其中某字形未识别 | 解 PUA 或加第三拆字源 |
| `-1` | 50 | 三个字根 + 一位；其中 **20 条**已判为识别码，30 条是四码字漏拆 | 码驱动拆法搜索（报告 242 §4） |
| `< -1` | 11 | 单组件（成字字根/独体），缺笔画序列 | 自编字根笔画（D18） |

## 4. 预期与实际的差距（如实记录）

报告 242 §5 曾估计"占位可把 full 提到约 807"。**实际没做到，也不该做到**：
54 条 A 类里有字形未识别，按 v3 规则只能是 `partial`。
真实收益是：**20 条识别码推导恢复** + **380 个占位位置带上了键位** + 6 条因 D3 修复转 `full`。
把 full 数量当目标会诱惑我们把"未知字形"说成"已知"，这条线不能松。

## 5. 校验与测试

- `tests/validate_b0.py`（v3）新增：含占位不得判 `full`、占位必须带键位、`keys` 与 `components` 等长、
  组件不得含空白或私有区字形（正是本次缺陷的回归拦截）；
- `platforms/macos/tests/test-hanzi-structure-b0.py` 新增占位契约用例；
- `make verify` + `make macos-offline-tests` 全绿。

## 6. 复现

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
```
