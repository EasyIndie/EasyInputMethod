# 五笔拆字标准 v1（项目统一口径）

> 状态：**ADR-358 采纳（2026-11-15）**。适用于本项目的 B0 结构事实库与后续多方案扩展。

## 1. 为什么需要项目标准

五笔 86 有公开的字根表与取码规则，但**没有针对全部 27,823 字的统一逐字拆字国标**；不同实现（rime、极点、搜狗、王码）对生僻/异体字会有不同拆法。业内可引用的标准是：

- 王码 86 官方字根表与取码规则（本项目的规范基础）；
- Unicode IDS / Unihan kIDS（结构分解，D19，MIT）；
- Academia Sinica CDP（部件/结构事实，D26，GPL-3 + 附加条款）；
- 《现代汉语通用字笔顺规范》（常用字笔顺）。

本项目不再追逐“某一份外部拆字表全量对齐”，而是定义一套**可审计、可复现、可扩展到 98/新世纪**的拆字标准。

## 2. 标准 v1 规则

一个 B0 合体字判为 `full`，必须同时满足：

1. **组件是标准字根**：每个组件必须出现在该方案的 `root-inventory.tsv` 中；
2. **键位一致**：组件在清单中允许的键位必须等于全码对应位；
3. **识别码一致**：组件数 = 码长 - 1 时，末位识别码必须与末笔+结构一致；组件数 = 码长时无识别码；
4. **结构一致**：结构以识别码为准；无识别码时用 CDP/IDS 作参考，冲突只记录；
5. **不猜**：占位组件、未知字根、算法拆解一律 `partial`/`unknown`，不得判 `full`；
6. **可追溯**：每条 `full` 记录带 `scheme`、`standardVersion`；数据来源与 SHA 在 `provenance` 与 `data/sources.toml` 登记。

数据来源只作**证据**，不直接决定身份：D2（MIT）是 canonical 拆字主源；cjk-decomp（Apache-2.0）只在树切分后逐叶键位/结构全匹配时采纳；CDP（GPL-3）只补结构/笔数，不补五笔字根；D3（未声明许可）仅构建期 oracle，不进产物。

## 3. 方案参数化（98 / 新世纪）

标准逻辑与方案数据分离：

```text
modules/hanzi-structure/schemes/
  wubi86.toml          # 当前：字根清单、码表、键位、识别码表
  wubi98.toml          # 未来：98 版字根表/码表（需许可来源）
  wubi-new-century.toml# 未来：新世纪版
```

每个方案提供：

- `root_inventory`：字根 → 允许键位；
- `code_table`：全码表；
- `key_roots` / `readable_keys`：键位事实；
- `recognition`：末笔 × 结构 → 识别码；
- `data_sources`：该方案允许的拆字/结构来源。

**通用部分**：校验逻辑、`standardVersion`、B0 schema、N2/N3 结构层、IDS/CDP 结构参考、测试与报告流程。
**不通用部分**：86/98/新世纪的字根表、键位、码表、识别码规则和拆字数据必须各自提供；不能把 86 的拆字表直接套到 98/新世纪。

因此：**逻辑通用，数据不通用**。98/新世纪预留同一标准接入点，**当前不实现**；需要各自的许可数据与方案 profile，结构/笔数/IDS/CDP 层可共享。

## 4. 当前 86 profile 的落地

- 字根清单：`data/learning/wubi86-root-inventory.tsv`（240 条 root/key，含标准变体）；
- 拆字来源：D2（MIT）、D24 cjk-decomp（Apache-2.0，树切分+键位/结构校验）；
- 结构：识别码 > CDP/IDS；CDP 通过 `檢字表.連接符號` 提供 1/2/3 结构；
- 笔数：D18 真实笔顺（56 成字字根）+ CDP/Unihan 笔数校验；
- 验收：`validate_b0.py` 强制 full 条目 `positionMismatch` 为空；B0 report 记录 `scheme`/`standardVersion`/`standardMismatchEntries`。

## 5. 结果与边界

标准 v1 落地后，B0 3,000 字 `full` 2,578 / `partial` 268 / `unknown` 154；1,000 字 `full` 916 / `partial` 80 / `unknown` 4。相比未加标准的 2,759，减少的条目主要是 D2 组件不在标准字根清单、或末位识别码槽/键位不能自洽的条目；它们被如实降为 `partial`，不再“看起来 full”。

全量 27,823 的 canonical 五笔拆字仍受外部数据限制：CDP/cjk-decomp/IDS 是结构部件，不是五笔码位拆字；D3/inputx 不能用/不采用。标准的作用是**保证已判 full 的每条都可审计**，而不是承诺 100% 覆盖。
