# 290 — 练习键盘导航、宿主内组合、使用指南结构化

日期：2026-11-16　设备：air（arm64 / macOS 27.2）
结论：三项改动**离线回归全绿**、**隔离预览实机 PASS**；尚未进入已装包（本地 ad-hoc 构建按规则不可安装），
正式候选验证留待下一次 CI 公证包。

## 1. 起因（用户反馈三条）

1. 练习页答完后只能鼠标点工具栏「下一题」，没有键盘快速前后切换，也没有回看上一题的路径。
2. 在输入法自己的符号面板搜索框里切到中文态打不出候选，怀疑是按应用记忆的中英状态错乱。
3. 使用指南每步是一段长文字，快捷键混在句子里，版式不够清晰。

## 2. 结论与改动

| 项 | 决策 | 代码 |
|---|---|---|
| 练习导航 | 内容区固定 `← 上一题 / 看答案 / 下一题 →`；回车未作答=提交、已作答=下一题；`←/→` 回看历史不重复计分；工具栏删「下一题/显示答案」 | ADR-362、`Practice.swift`、`PracticeWindow.swift`、`PracticeAnswerView.swift` |
| 宿主内输入 | 根因是 **IMK 不能给自己的宿主进程当客户端**（与 `AppLanguageMemory` 无关）；用同一 `ImeSession` 做进程内组合，只对显式 `attach` 的中文字段生效 | ADR-363、`InHostTextInput.swift`、`SymbolPickerWindow.swift`、`UserDictionary.swift`、`PassageWindow.swift` |
| 使用指南 | `summary` + `bullets`（键帽 + 短句）结构化，6 步，键帽/项目符号/步骤点绘制，窗口高度自适应 | ADR-364、`OnboardingWindow.swift` |

顺带修掉：判分后重复按回车会**再记一次分**（引擎与 UI 两侧都加了"本题已作答即拒绝"）；
工具栏「下一题（回车）」的错误 tooltip 随按钮一起删除。

## 3. 离线门禁

| 门禁 | 结果 |
|---|---|
| `platforms/macos/tests/test-wubi-learning.py` | PASS（含新增历史回看/不重复计分/导航行断言） |
| `platforms/macos/tests/test-onboarding-guide.py` | PASS（6 步、1–3 条/步、快捷键独立成键帽、翻页） |
| `python3 platforms/macos/tests/run-offline-tests.py` | **68 文件 / 337 例 PASS**，6 并发 45.1s |
| `./platforms/macos/build.sh --strict` | PASS（含逐架构网络导入检查） |
| `make macos-ui-snapshots` | PASS；`guide-{light,dark}-step{1,4}.png` 显示键帽、项目符号、步骤点与自适应高度 |

## 4. 隔离预览实机（`run-panel-interactive.py`，私有根 `lampyris-panel-*`）

测试进程 `LampyrisIsolated`（预览编译同一套 Sources），输入源临时切 ABC、会话结束还原；
真实 `config.toml` / `user-dictionary.tsv` 未变（脚本自检 `PASS interactive cleanup … real files unchanged`）。

| 场景 | 证据 |
|---|---|
| ⌥K 打开练习（隔离根） | AX：窗口「萤火虫 · 练习」，题面「土 / 这个字根在哪个键上？（1 位）」，导航行三按钮（上一题禁用） |
| 答对后回车不自动跳 | 输入 `f` + 回车 → `✓ 正确 · 你答 F`；统计 `7 次`；上一题仍禁用（历史只有 1 条） |
| 回车进下一题 | 再回车 → 题面「山」，统计 `8 次`（只 +1，无重复计分），上一题变可用 |
| `←` 回看 | 答完「山」后 `←` → 题面「土」+ `✓ 正确 · 你答 F` + 下一题 tooltip「下一题（→，回到更新的题）」，统计仍 `9 次` |
| `→` 前进 | 回到「山」+ `✓ 正确 · 你答 M`，统计不变（回看不写进度） |
| 未作答时 `←` | 不动（符合"避免误跳过"） |
| ⌥C 符号面板搜索 | 输入 `nihao` → 预编辑 `nihao`、候选窗 504×98（`1/2` 页、`←→浏览 · 空格确认 · 数字直选`） |
| 空格上屏 | 搜索框变 `你好`，「找到 6 项」，候选窗收起 |
| 数字直选 + 分段选词 | 重新输入 `nihao` 后按 `2` → 先上屏 `你`、余码 `hao` 继续组合（ADR-330）；空格后 `你好` |
| 收尾 | 关闭面板与主窗口，进程正常退出（`PASS interactive cleanup`），输入源还原 `Lampyris.default` |

## 5. 差异与遗留

- **未在已装包验证**：本机只能构建 ad-hoc 包（无本地 ASC 公证凭据），`install.sh` 的 Developer ID + 公证硬校验
  会拒绝安装；三项改动需随下一次 `dev → main` 的 CI 公证候选做一次真机复验（练习导航键、宿主内搜索中文、
  指南版式）。本报告不把预览结论当已装包 PASS。
- 宿主内组合刻意不复制 IMK 侧策略（热键、标点、学习区），只覆盖"中文字段能打出字"这一收敛点；
  以后引擎新增候选/分页能力会自动生效（同一 `ImeSession`）。
- 符号搜索的"拼音/英文"索引仍按原数据（emoji 有拼音列、符号只有关键词列）；中文上屏后走中文关键词匹配。
