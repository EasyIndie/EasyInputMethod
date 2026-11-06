# B0 结构事实库 · 数据模型（试点 1,000 高频字）

> 状态：**B0 试点**（ADR-189 的第一次落地）。只读事实库，不进入输入热路径，不改候选排序。
> 版本：`schemaVersion: 3`（v3 允许**占位组件** `null` + 键位推断，见报告 243；v2 见报告 241）。字段变更必须升版本并写报告。

## 1. 目的

给"学 / 练"提供**每字可解释**的事实：这个字怎么取码、末笔与结构如何决定识别码、有没有简码。
判定标准是"讲解**能追溯到事实**"，不是"字段多"。

## 2. 字段

| 字段 | 类型 | 说明 |
|---|---|---|
| `char` | string | 单字 |
| `code` | string | 五笔86 全码（来自 D1 生成码表） |
| `class` | enum | `key-name`（键名字）/ `radical-char`（成字字根）/ `compound`（合体字） |
| `components` | (string\|null)[] | 字根序列（可读字形；**不含任何 PUA 字形**）。`null` = **占位组件**：位置已知、字形未识别，键位见 `keys` |
| `componentsSource` | enum | `D2` / `D3` / `null`：组件来自哪一份拆字源（报告 241：D2 优先，D3 兜底） |
| `keys` | string[] | 每个字根对应的键位字母（取全码同位置；含占位组件时同样成立，故 `len(keys) == len(components)`） |
| `recognition` | object \| null | `{key, stroke, structure, because}`：识别码字母、末笔、结构、判定依据 |
| `short1` / `short2` | string \| null | 一级 / 二级简码（D17 / D17-bis） |
| `pinyin` | string \| null | 首选读音（D5） |
| `frequency` | int | 通用字频（D10，jieba 单字频；0 表示缺） |
| `quality` | enum | `full` / `partial` / `unknown`，见 §4 |
| `notes` | string[] | 缺口与不确定点（**不允许**留空的"看起来完整"） |

## 3. 判定规则（全部来自已登记数据，不引入新来源）

1. **键名字**：全码 4 位且四位相同 → `class=key-name`，`because="键名字，连打该键四次"`。
2. **成字字根**：D2 字形序列首位 == 该字 → `class=radical-char`，后续字形是笔画（可读，如 一丨丿丶乙）。
3. **合体字**：D2 可读字形即字根序列；`n = len(components)`
   - `len(code) == n + 1` → 末位是**识别码**：`(stroke, structure) = inverse(末位)`；
   - `len(code) == n` → **无识别码**（字根已够四码）；
   - 其它 → `quality=partial`，`notes` 记录 `code_len` 与 `n` 的具体数值。
4. **PUA 处理**：补充区（≥U+F0000）与 BMP 私有区（U+E000–U+F8FF）**一律不得进入产物**。
   先查 `pua-map`（`tools/decode_pua.py` 从 D2/D3 对齐学出）；查不到的 BMP 字形**保留为占位组件 `null`**
   （v3）：位置仍参与"组件数 ↔ 码长"判定，键位由码位推断（第 i 个组件 ↔ `code[i]`），
   该字降级为 `partial` 且 notes 写明「第 k 个字根（键 x）字形未识别」。
   占位让识别码推导重新成立（报告 242：54 条 A 类），但**不得**因占位而判 `full`。
5. 识别码反查表（末笔 × 结构）：横 GFD / 竖 HJK / 撇 TRE / 捺 YUI / 折 NBV（各自顺序=左右、上下、杂合）。

## 4. 质量等级

| 等级 | 含义 |
|---|---|
| `full` | 三类之一判定成功，组件**全部可读**，且（合体字）能给出识别码依据或无识别码结论 |
| `partial` | 有码，但字根数/码长对不上，或含**占位组件**（字形未识别） |
| `unknown` | 缺码或缺拆字数据 |

**发布规则**：`partial` / `unknown` 允许存在，但必须带 `notes`；对外讲解时按等级降级表述，
不得把 `partial` 当完整解释。

## 5. 产物

- `corpus/B0.json`：数组，按 `frequency` 降序、`char` 升序；
- `corpus/B0-report.json`：覆盖统计、输入文件 SHA-256、生成命令；
- 两者都由 `tools/build_b0.py` 生成，`tests/validate_b0.py` 独立复核。

## 6. 消费契约（谁能展示什么）

**方案 A（报告 241 决定）**：接受 76% 的 full 覆盖率，但**按等级降级表述**，绝不把 partial 当完整解释。

| 质量 | 允许展示 | 禁止 |
|---|---|---|
| `full` | 编码 + 字根 + 字根键位 + 识别码依据（末笔×结构）+ 简码 + 读音 | — |
| `partial` | 编码 + 简码 + 读音 + 键位序列（占位组件显示 `？`）+ **「拆解待核验」**；若 `recognition` 存在，必须标注「参考」 | 不得只讲拆解不讲"待核验"；不得用于考核判分；不得把占位组件当成已知字形 |
| `unknown` | 编码或"无数据" | 不得展示任何拆解 |

实现约定（供 L3 候选窗 / L4 练习题使用）：

1. 判分（练习对错）**只允许**用 `full` 条目出题；
2. `partial` 只能出现在"查询/提示"路径，且必须带降级文案；
3. `unknown` 只用于"这个字暂缺资料"的说明。

机器约束：`tests/validate_b0.py` 检查"非 full 必须有 notes""recognition 必须能对上码长和组件数""含占位组件不得判 full""keys 与 components 等长"，
`tools/b0_query.py` 是这套契约的参考实现（可直接看输出格式）。

## 6. 边界（ADR-189）

- 本目录不依赖 `ime-*`、平台代码或主仓库路径；工具的输入输出全部由命令行显式给出。
- 事实来源许可与 SHA 见 `provenance/B0.md`；PUA 与私有字形不进入本库。
- 不改变输入法行为；运行包/接入方式另定（ADR-189「产物边界」）。
