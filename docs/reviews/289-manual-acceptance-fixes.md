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

## 4. 预览输入区不消费打开类快捷键

**现象**：在 `make macos-dev` 的输入框里按 `⌥C`/`⌥K`/`⌥G`，快捷键不生效，反而把 Option 字符插入文本。

**原因**：正式宿主在 `handleHotkey` 里先处理 `open_update/open_practice/open_symbols`，再交给
`session.shortcut`；预览的 `PreviewInput.handleShortcut` 只处理了设置/关于，缺少这三个入口。

**处理**：

- 预览补齐 `onOpenUpdate` / `onOpenPractice` / `onOpenSymbols`，与菜单回调共用同一个符号插入闭包；
- 预览冒烟新增断言：合成 `⌥C`/`⌥K`/`⌥G` 事件必须分别触发对应回调，不能被当作文本插入。

## 5. 预览里 ⌥M/⌥F/⌥P/⌥T 仍不生效

**现象**：补齐预览的打开类快捷键后，`⌥C/⌥K/⌥G` 正常，但 `⌥M/⌥F/⌥P/⌥T` 仍无反应。

**定位**：

- 预览冒烟（合成事件 + 私有配置）里四个状态键**全部通过**：`⌥M` 切模式、`⌥F` 全半角、
  `⌥P` 标点、`⌥T` 简繁；说明预览代码路径与持久化写入都正常。
- 当前系统输入源是 `cn.jokerhub.inputmethod.Lampyris.default`（已装输入法）。IMK 会在系统层
  先把这些 ⌥ 快捷键交给已装宿主；预览窗口收不到。会话期间真实 `config.toml` 被改成
  `punctuation=english / full_width=full / chinese_variant=traditional`，正是这四个键的效果。
- `⌥C` 之所以正常，是因为已装 1.3.0 的符号键还是 `⌥S`，不认识 `⌥C`，事件才落到预览。

**处理**：

- `make macos-dev` 启动时查询当前输入源；若是萤火虫，**自动切到 ABC**，关闭窗口/异常退出时
  在 `finally` 里切回原输入源（实测双向 `tissrc select` 均生效）；切换失败时打印手动提示；
- 预览冒烟新增四个状态键的断言（模式/全半角/标点/简繁各切换一次），防止回归；
- 这是输入法系统的预期行为，不是预览或产品的 bug；自动化只改变本机输入源并在会话结束时还原。

## 6. 验证

- `test-wubi-learning`：新增 `.code3` 答案 3 位与判分断言，题库非空；
- `test-symbol-picker`、`test-ui-snapshots`、三处菜单探针 PASS；
- `make macos-ui-snapshots`：新增指南快照（亮/暗 × 第 1/4 步）；
- 预览冒烟新增状态快捷键断言；`make macos-offline-tests` 68 文件 / 337 例 PASS；`make verify` PASS。

## 7. 关联

ADR-361、ADR-345/314、报告 288、`OnboardingWindow.swift`、`Practice.swift`、
`PracticeWindow.swift`、`PracticeExplanationView.swift`、`Preview/main.swift`、
`run-panel-interactive.py`、`dev-preview.sh`。
