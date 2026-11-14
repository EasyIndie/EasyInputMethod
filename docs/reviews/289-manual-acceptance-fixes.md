# 289 — 人工验收三项修复：指南布局 / 预览数据 / 三级简码练习

> 2026-11-15。用户在隔离预览窗口验收时反馈的三项问题。

## 1. 使用指南下半部分空白

**现象**：指南窗口 560×380，内容都在上半部，下半部大片空白。

**处理**：

- 窗口高度 380 → **260**；
- 布局改为两栏：左侧图标/标题/正文，右侧 132×132 的步骤图示卡片（强调色 10% 底、
  56pt SF Symbol），把原来的空白变成视觉锚点；
- 新增 `OnboardingWindow.renderForTesting` 与 `guide-{light,dark}-step{1,4}.png` 快照，
  以后改布局可直接对比。

## 2. 符号 / emoji 面板「缺少 symbols.tsv」

**现象**：预览的符号面板只有搜索框和「其他」分类，底部报「缺少 symbols.tsv」，
无法搜索或插入。

**原因**：隔离预览 App 只软链了 `Resources/data`，但 `SymbolCatalog` 按正式包的方式从
`Contents/Resources/symbols.tsv`、`emoji.tsv` 读取；学习提示（`B0-runtime.tsv`）、
词组题库（`wubi86-core.tsv`）同样缺失。

**处理**：

- `run-panel-interactive.py` 把预览包 `Contents/Resources/` 下的数据文件**全部软链**到隔离 App，
  以后新增资源不会再漏；
- `dev-preview.sh` 补齐 `symbols.tsv`、`emoji.tsv`、`wubi86-core.tsv`、`wubi86-level3-codes.tsv`；
- 快照/预览仍只读仓库数据，不写真实配置。

## 3. 练习没有三级简码

**现象**：练习分段只有「字根 / 一级 / 二级 / 完整码 / 词组 / 识别码」。

**处理**（ADR-361）：

- 新增 `PracticeKind.code3`，插在二级与完整码之间；
- 题库只对 **D17-ter 权威表**里明确收录的 `full` 字出题，绝不把「完整码前 3 位」当简码；
- 作答框 3 格，拆解说明追加「三级 XXX」；
- `wubi86-level3-codes.tsv` 随包分发；预览/隔离 App 也已带上；
- 指南第 4 步的题型顺序同步。

## 4. 验证

- `test-wubi-learning`：新增 `.code3` 答案 3 位与判分断言，题库非空；
- `test-symbol-picker`、`test-ui-snapshots`、三处菜单探针 PASS；
- `make macos-ui-snapshots`：新增指南快照（亮/暗 × 第 1/4 步）；
- `make macos-offline-tests` 68 文件 / 337 例 PASS；`make verify` PASS。

## 5. 关联

ADR-361、ADR-345/314、报告 288、`OnboardingWindow.swift`、`Practice.swift`、
`PracticeWindow.swift`、`PracticeExplanationView.swift`、`run-panel-interactive.py`、`dev-preview.sh`。
