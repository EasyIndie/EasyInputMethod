# 282 — N1-d 覆盖扩量（星号兜底 / D2 BMP / 逐字语境）

> 2026-11-14。**只扩数据覆盖，不改输入行为；D3 仍只作 oracle。**
> 后续报告 283（D24 cjk-decomp，Apache-2.0）把 B0 3,000 字 `full` 再推到 2,740、`unknown` 降到 172；本文数字保留为当时结果。

## 1. 做了什么

在 N1-d 的 66 条 `(PUA, 键位)` 核验基础上，新增三类**无歧义**映射：

| 文件 | 条数 | 内容 |
|---|---:|---|
| `pua-supplementary.tsv` 的 `*` 行 | 62 | 在所有已见语境都为同一部件的 PUA（如 龷、彐、亠、隹、鱼、马、雨、虍…） |
| `pua-d2-bmp.tsv` | 3 | D2 的 BMP PUA：U+E816→𠂇、U+E826→手/三（按键位） |
| `pua-context.tsv` | 34 | 同一 PUA 在不同字里指不同部件：氏/卯、才、乚/匕、儿 |

`build_b0.py` 的解码顺序：**逐字语境 → `(PUA, 键位)` → `(PUA, '*')`**；BMP PUA 同样先查语境/D2 BMP 表，再查 `pua-map`。所有 PUA 仍不进入产物。

## 2. 结果

| 指标 | 前（报告 281） | 后 |
|---|---:|---:|
| B0 1,000 字 `full` | 927 | **955** |
| B0 1,000 字 `partial` | 65 | **37** |
| B0 1,000 字 `unknown` | 8 | 8 |
| B0 3,000 字 `full` | 2,588 | **2,676** |
| B0 3,000 字 `partial` | 192 | **104** |
| 运行时 `full` | 2,462 | **2,519** |
| 运行时 `partial` | 318 | **261** |
| 运行时 `unknown` | 220 | 220 |
| 占位条目（3,000） | 155 | **66** |

运行时（学习区实际消费）`full` 2,519（84.0%）；B0 `full` 2,676（89.2%）。

## 3. 剩余 220 个 `unknown`

全部有全码、有 IDS，但 **D2 没有拆字**；绝大多数是繁体/生僻字（紝、銆、鐨、簡、鏈、購、鏃…）。
D3 有这些字的拆字，但 D3 是未声明许可的构建期 oracle；按 ADR-310 不能作为 `componentsSource`。
本轮**没有**用 D3 批量补数。

可选下一步（需单独决定）：
1. 引入有许可的完整拆字源；
2. 或批准「D3 oracle 候选 + 全组件键位/结构校验 → D18 项目自编」的方案（需 ADR，且逐条可审计）；
3. 或把 3,000 字口径改为「简体高频字」并单列繁体覆盖。

## 4. 运行时与 B0 的差异

少数新 `full` 在运行时仍显示 `partial`，因为 `positionMismatch` 会截断：
例如「我」的 D2 末位是识别码字形「丶」，B0 判 full，运行时从第 4 位截断后仍按 partial 展示。
这是**保守展示**，不是数据回归；报告 281 §8 已说明。

## 5. 验证

- `validate_b0.py` PASS；
- `test-pua-inventory.py` / `test-pua-maps.py` / `test-hanzi-structure-b0.py` PASS；
- `make macos-offline-tests`、`make verify`。

## 6. 关联

ADR-353/355/356、报告 280/281、`data/sources.toml` 的 `wubi-pua-supplementary` /
`wubi-pua-d2-bmp` / `wubi-pua-context` / `pua-inventory`。
