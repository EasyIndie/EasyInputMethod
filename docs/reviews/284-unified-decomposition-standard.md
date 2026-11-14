# 284 — 五笔拆字标准 v1 落地（ADR-358）

> 2026-11-15。**统一口径；不承诺 100% 覆盖，但 `full` 必须可审计。**

## 1. 标准

新增 `docs/standards/wubi-decomposition.md`：`full` 必须同时满足

1. 组件在方案标准字根清单；
2. 组件键位 = 全码对应位；
3. 识别码与末笔+结构一致；
4. 结构与识别码/CDP/IDS 一致；
5. 非算法拆解、非 PUA、非猜测。

落地产物：

- `data/learning/wubi86-root-inventory.tsv`：237 条 root/key（官方字根 + 标准变体）；
- `build_b0.py --root-inventory`；
- B0 schema **v7**：`scheme` / `standardVersion`；`positionMismatch` 成为标准诊断，`full` 必须为空；
- `validate_b0.py` 强制上述契约。

## 2. 结果

| 指标 | 标准前 | 标准后 |
|---|---:|---:|
| B0 1,000 字 `full` | 965 | **910** |
| B0 1,000 字 `partial` | 31 | **86** |
| B0 1,000 字 `unknown` | 4 | 4 |
| B0 3,000 字 `full` | 2,759 | **2,554** |
| B0 3,000 字 `partial` | 87 | **292** |
| B0 3,000 字 `unknown` | 154 | 154 |
| 运行时 `full` | 2,602 | **2,554** |
| `standardMismatchEntries` | — | 267（3,000）/ 81（1,000） |

减少的 `full` 不是数据丢失，而是把「D2 组件不在标准字根清单、末位识别码槽/键位不能自洽」的条目
如实降为 `partial`；它们不再以完整解释展示。

## 3. 98 / 新世纪

标准逻辑与方案数据分离：

- 通用：校验逻辑、B0 schema、N2/N3、IDS/CDP 结构层、测试/报告；
- 不通用：86/98/新世纪的字根表、码表、键位、识别码规则、拆字数据。

因此 98/新世纪**可以复用同一标准**，但必须各自提供方案 profile 与许可数据；不能把 86 的拆字表直接移植。
`docs/standards/wubi-decomposition.md` 给出 `schemes/*.toml` 的字段约定。

## 4. 仍未完成

- 全量 27,823 的 canonical 五笔拆字仍缺公开权威逐字表；CDP/cjk-decomp/IDS 是结构部件，不是五笔码位拆字。
- 293 条 partial 主要是：标准字根清单未覆盖的变体、D2 位次/识别码不自洽、占位 PUA。
- 标准 v1 不承诺 100% 覆盖；后续可逐步补标准变体与结构数据，但不放松 `full` 门槛。

## 5. 验证

- `validate_b0.py` PASS（full 无 `positionMismatch`）
- `test-hanzi-structure-b0.py`、`test-cjkdecomp-coverage.py`、`test-pua-*.py`
- `make macos-offline-tests`、`make verify`

## 6. 关联

ADR-358、`docs/standards/wubi-decomposition.md`、`data/learning/wubi86-root-inventory.tsv`、
`B0-schema.md`、`provenance/B0.md`。
