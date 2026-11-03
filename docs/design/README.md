# 设计稿目录

这里存放**界面设计的过程产物**（SVG/PNG 稿、渲染脚本、原生色值参考），不是产品契约。
产品行为的权威描述在 [`../技术方案.md`](../技术方案.md) 与 [ADR](../决策记录.md)；能跑的界面在 `platforms/macos/`。

## 当前生效

| 目录 | 内容 | 状态 |
|---|---|---|
| `compact-learning-v10/` | 当前候选窗 + 紧凑学习区（长词/学习区最终形态） | **生效**（1.0.0 实机外观以此为准，形状由 `CandidateWindow.swift` + `CaretPlacement.swift` 落地） |
| `产品页视觉规范.md` | 线上产品页视觉规范 | 生效（站点 `site/`） |

## 历史迭代（保留溯源，勿据此改代码）

`candidate-v3` → `candidate-v4` → `candidate-v5` → `learning-v6` → `candidate-v7` → `candidate-v8` → `long-word-v9` → `compact-learning-v10`
是候选窗/学习区的连续迭代，后者取代前者。`mvp-ui.md`、`mvp-ui-review/`、`mvp-complete-ui-review/`、`macos-native-v2/`、`macos-2026/`、`review-20261014/` 属同一批过程稿。

## 使用约定

- 想改界面 → 先看 `compact-learning-v10/` 与 `CandidateWindow.swift` 的现状，再按 ADR 流程决定是否新增迭代目录。
- 新增迭代用 `新主题-vN`，并在本文件登记"生效/历史"状态。
- 过程稿不进 `/site`、不打包进发布产物。
