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

## 5. 本地开发包初验（`run-panel-interactive.py`，独立会话）

同一套 Sources 的隔离预览进程（`LampyrisIsolated`，私有根 + `LAMPYRIS_SUPPORT_DIR`），输入源临时 ABC、
结束 `PASS interactive cleanup … real files unchanged` 并还原 `Lampyris.default`。
证据目录 `platforms/macos/build/acceptance-local-dev-1brtugym/`（本机产物，不入库）。

| 项 | 观测 | 结果 |
|---|---|---|
| 预览菜单顺序 | 混输/中文/半角/简体/标点 → 显示学习区 → 练习… → 符号与表情… → 使用指南… → 检查更新… → 设置… → 关于 | PASS |
| 练习基线（私有根） | `已练 0 字 · 0 次 · 0%`（证明练习数据写私有根，见 §6） | PASS |
| ⌘↩ 看答案 | AX 出现拆解文本 `言，键 Y；键位 Y；三级 YYY`；统计仍 `0 次` | PASS |
| 错误作答 | 输入 `a`+回车 → `✗ 再想想 · 你答 A`，`1 次`；上一题仍禁用（历史 1 条） | PASS |
| 回车进下一题 | 题面换新（子），`1 次`（只 +1，无重复计分），上一题可用 | PASS |
| 未作答按 ← | 题面不变（避免误跳过） | PASS |
| ← 回看 | 答完第二题后按 ← → 题面回到「言」+ `✗ 再想想 · 你答 A`；tooltip 变「下一题（→，回到更新的题）」；统计仍 `2 次` | PASS |
| → 前进 / 越过历史 | → 回到「子」保留当时的 ✗；再 → 得到未作答新题（看答案可用、无反馈） | PASS |
| 鼠标「下一题 →」 | 点击换题，统计不变 | PASS |
| 工具栏 | 只剩 文章跟打 / 键位图 / 重置进度 / 进度文件 | PASS |
| 符号面板组字 | `nihao` → 搜索框预编辑 + 候选窗 504×98（`←→浏览 · 空格确认 · 数字直选`） | PASS |
| Esc 取消组字 | 预编辑清空、候选窗收起、面板不关 | PASS |
| 空格上屏 | 搜索框变 `你好`，状态「找到 6 项」，候选窗收起 | PASS |
| 数字直选 + 分段选词 | `2` 先上屏 `你`、余码 `hao` 继续组合（ADR-330），再空格 → `你好` | PASS |
| 指南 6 步与自适应高度 | 步 1 620×252、步 2 620×264、步 6 620×252；步 2 键帽 AX 文本 `⌥M 混合 / 五笔 / 拼音 循环`、`⌥P ⌥F ⌥T 标点 · 全半角 · 简繁`；末步按钮变「完成」 | PASS |
| 收尾 | ⌘Q 退出 → `PASS interactive cleanup: owned process exited; real files unchanged`；输入源回到 `Lampyris.default` | PASS |

中途「Herdr」抢过前台一次：按守则停在按键批次前，重新激活自有测试 App 并复核 `guard-focus` 后继续，
未向其它应用投递按键。

## 6. 本轮发现并修复的验收隔离缺口

隔离预览只把 `config.toml` 指到私有根，**练习进度/薄弱字仍经 Swift 侧 `ImePaths` 落到真实目录**：
初验第一轮把 6 条字根记录写进了真实 `~/Library/Application Support/Lampyris/practice.tsv`
（该文件此前不存在，均为本轮测试生成，已删除还原）。
修复：`run-panel-interactive.py` / `run-panel-isolation.py` 启动时加 `LAMPYRIS_SUPPORT_DIR=<私有根>`，
并把 `practice.tsv` / `weak-chars.tsv` 纳入 protected 断言；`run-panel-isolation.py` 四模式复跑 PASS。
另把 `PracticeExplanationView` 设为可读的无障碍元素（`AXStaticText`），否则「看答案/判分后」的拆解
对 VoiceOver 不可见（本报告的 AX 证据也依赖它）。

## 7. 已装包初验（两轮候选）

### 7.1 `a925011`（执行 `b90ec496…`）——练习 PASS / 符号 FAIL

| 项 | 观测 | 结果 |
|---|---|---|
| 新二进制 | 执行 `b90ec496…`、`SOURCE-COMMIT=a925011`、`lsof` 无 deleted；`wq ` → 你（p50 3.62ms） | PASS |
| 菜单顺序 | 与 ADR-360 一致（学习区→练习→符号→指南→检查更新→设置→关于） | PASS |
| 练习导航 | 答错 → `✗ 再想想 · 你答 A`（1 次）；回车进下一题（仍 1 次）；答第二题后 `←` 回看「戋」保留 ✗、tooltip 变回看版、次数不变；`→` 前进；按钮「下一题 →」「看答案」可用；工具栏只剩 4 项；`看答案` 显示 `丶，键 Y；键位 Y；三级 YYL` | PASS |
| 符号面板中文 | 搜索框收到裸 `nihao`、**无候选窗**、找不到符号 | **FAIL** |

**失败根因**：面板是非激活窗口，按键不是走 App 事件循环，而是由 IMK `handle` 转给
`SymbolPickerWindow.handleKey`；进程内组合只装了本地事件监视，看不到这条转发路径。
修复：`InHostTextInput.handleForwardedKey(_:field:)`（与本地监视共用 `ImeSession` 与候选窗，
预编辑串显示在候选窗输入码，上屏文本由面板写回搜索框），并在 `handleKey` 里先于面板自身导航处理。
`test-symbol-picker.py` 新增转发路径断言（字母组合、Esc 取消、空格上屏、未组合放行、⌘ 放行）。

### 7.2 `edb6d7c`（执行 `1d6bac79…`）——全部 PASS

CI run `43860624079`，ZIP `shasum -c` ✅、Developer ID + hardened runtime、`stapler validate` ✅、
`spctl` = `Notarized Developer ID`；`--keep-data` 安装，配置 `248f4591…` 未变。
证据目录 `platforms/macos/build/acceptance-air-edb6d7c/`（本机产物，不入库）。

| 项 | 观测 | 结果 |
|---|---|---|
| 新二进制 | `SOURCE-COMMIT=edb6d7c`、执行 `1d6bac79…`、`lsof` 无 deleted；`wq ` → 你（3 键，p50 5.65ms） | PASS |
| 符号面板中文（本轮重点） | ⌥C → `nihao`：候选窗 537×98、输入码 `nihao`、提示 `←→浏览 · 空格确认 · 数字直选`；空格 → 搜索框 `你好`、「找到 6 项」；Esc → 取消组字且面板不关、字段不变；数字 `2` 直选提交候选（当页第 2 项为 `你好吗`） | PASS |
| 练习导航 | 答错/答对各一次 → 回车进下一题、次数只 +1；`←` 回看上一题保留当时 ✓/✗、tooltip 变回看版、次数不变；`→` 前进同样不计分；「看答案」显示 `禾，键 T；键位 T；三级 TTT`；工具栏只剩 文章跟打 / 键位图 / 重置进度 / 进度文件 | PASS |
| 使用指南 | 6 步；步 1 620×252、步 2 620×264（键帽 AX 文本 `⌥M 混合 / 五笔 / 拼音 循环`、`⌥P ⌥F ⌥T 标点 · 全半角 · 简繁`）、步 6 620×252（末步按钮「完成」） | PASS |
| 收尾 | 关闭所有窗口；删除本轮测试写出的 `practice.tsv`（测试前不存在）；配置仍 `248f4591…`；输入源保持 `Lampyris.default` | PASS |

环境备注：练习/指南窗口在含上下双屏的布局里会落在副屏（AX 坐标 y 为负），交互前用 AX 移回主屏；
这是窗口居中位置选择，不属本批缺陷，未改代码。

## 8. 差异与遗留

- **未在已装包验证**：本机只能构建 ad-hoc 包（无本地 ASC 公证凭据），`install.sh` 的 Developer ID + 公证硬校验
  会拒绝安装；三项改动需随下一次 `dev → main` 的 CI 公证候选做一次真机复验（练习导航键、宿主内搜索中文、
  指南版式）。本报告不把预览（本地开发包）结论当已装包 PASS。
- 宿主内组合刻意不复制 IMK 侧策略（热键、标点、学习区），只覆盖"中文字段能打出字"这一收敛点；
  以后引擎新增候选/分页能力会自动生效（同一 `ImeSession`）。
- 符号搜索的"拼音/英文"索引仍按原数据（emoji 有拼音列、符号只有关键词列）；中文上屏后走中文关键词匹配。
