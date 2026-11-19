# LWS-86 一致性测试 1.0

> 判定程序：`python3 tools/wubi86-std-check.py`（第三方实现亦可用）。
> 规则编号与 [`spec-1.0.md`](spec-1.0.md) §5 对应；本文件只描述"怎么判"和"判什么"。

## 1. 输入

| 参数 | 说明 |
|---|---|
| `--bundle <dir>` | 标准数据包目录（含 `chars.tsv` / `roots.tsv` / `shortcodes.tsv` / `SHA256SUMS`） |
| `--impl <dir>` | 待判定实现的数据目录（同格式；字段可少，但不能缺被判定等级的字段） |
| `--level L1\|L2\|L3\|L4` | 目标等级，默认 L2 |
| `--report <file>` | 输出机读报告（JSON：`passed` / `failures[]` / `coverage`） |

## 2. 判定项

| 编号 | 对应规则 | 判定方法 | 失败信息 |
|---|---|---|---|
| T1 | R1 | `chars` 里每个 full 条目，其 `roots[]` 的字形必须都在 `roots` 表内 | `<字>: 字根 <g> 不在标准字根表` |
| T2 | R2 | 逐位比较：`roots[i]` 在该表的允许键位 ∋ `code[i]` | `<字>: 第 i 个根 <g> 的键位不在 <code[i]>` |
| T3 | R3 | `len(roots) == len(code)`（无识别码）或 `== len(code)-1`（有识别码） | `<字>: 根数 N 与码长 M 不匹配` |
| T4 | R4 | `recognition.key == code[-1]`，且 `(stroke, structure)` 在网格中推出该字母 | `<字>: 识别码与网格不符` |
| T5 | R5 | L1：`impl.code == std.code`（范围内全部字） | `<字>: 码不一致 std=<a> impl=<b>` |
| T6 | R6 | L3：三级槽位逐条相等（`-` 表示缺项） | `<字>: 第 n 级简码 std=<a> impl=<b>` |
| T7 | R7 | 不满足 T1–T4 的条目不得是 `full` | `<字>: 应为 partial/unknown，却是 full` |
| T8 | L2 | `impl.roots[] == std.roots[]`（逐位字形相同） | `<字>: 根序不一致 std=<...> impl=<...>` |
| T9 | L4 | 对 full 条目，`recognition` 的 `(stroke, structure)` 与网格一致且 `reason` 非空 | `<字>: 缺少识别码理由` |

## 3. 覆盖与报告

- 报告必须包含：`scope`（标准声明范围内的字数）、`compared`、`passed`、`failed`、
  以及 `missing`（实现里缺失的条目，按 `partial`/`unknown`/缺失分别计数）。
- **等级只对范围内、且实现标为 `full` 的字判定**；实现可少覆盖（记 `missing`），但不得"多"覆盖到标准未收录的字而拒绝报告。
- 反例自检（`test-wubi86-standard.py` 会跑）：把任一字的 `code` 改一位、或把某根的键位改错，检查器 MUST 报 T5/T2 失败。

## 4. 退出码

| 码 | 含义 |
|---|---|
| 0 | 通过目标等级 |
| 1 | 未通过（报告里有 `failures`） |
| 2 | 输入不合法（缺字段、PUA、SHA 不符） |

## 5. 数据完整性

- 数据包 MUST 带 `SHA256SUMS`；检查器默认校验，`--no-verify-sha` 可跳过（仅调试用）。
- 任何表出现私有区码位（U+E000–F8FF、U+F0000+）→ 退出码 2。
