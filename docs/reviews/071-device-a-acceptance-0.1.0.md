# 071 — A 设备实机验收（0.1.0 正式包 a234ef31）

2026-10-18。对签名公证包 `a234ef31…`（源码提交 `ba6d796`，universal）在 A（Intel / macOS 13.7.8）上执行与 B（报告 [070](070-device-b-acceptance-0.1.0.md)）相同的可执行验收清单。全部动作在 A 的图形会话内完成（非 SSH）。

## 环境

| 项 | 值 |
|---|---|
| 硬件/系统 | `bot.local`，x86_64，macOS 13.7.8（22H730） |
| 已装包 | `~/Library/Input Methods/Lampyris.app`，执行 SHA `a234ef31…`（与 B 同一包） |
| 签名/公证 | `codesign --verify --deep --strict` 通过；`spctl` = Notarized Developer ID；`stapler validate` 通过 |
| 宿主 PID | 67948（全程未变；未换包、未重启、未热替换） |
| 输入源 | 测前 `com.apple.keylayout.ABC`（系统启用源：ABC / `Lampyris` / `Lampyris.default`） |
| `config.toml` | SHA `48259b19…`；`mode=mixed`、标点=中文、字形=简体、`full_width=true`（测前测后一致） |
| 用户词库 | `user-dictionary.tsv` 960 行；测中学习计数写入 1 字节（见「数据变化」） |
| 工具 | `tools/macos-probe/`（`axmenu`/`axtext`/`typekeys`/`keymod`/`selsrc`/`windows`），本机 `swiftc` 5.8.1 构建 |
| 文本宿主 | TextEdit + 自建文档 `/tmp/lampyris-a/acceptance-a.txt`（未碰用户真实文档/会话） |

> 与 HANDOFF 旧描述不同：本机**已有** `cargo 1.98.1` / `rustc 1.98.1`（`~/.cargo/bin`）。本轮未用其构建产品，只按任务要求用预编译包验收。

## 结果总览

| # | 步骤 | 结果 | 证据 |
|---|---|---|---|
| a | TextEdit 自建文档 + 按键一次激活控制器 | **PASS** | `01-activate-host.txt` |
| b | 菜单 7 个产品行 + 右侧快捷键 | **PASS（行数与任务描述不符，见「差异 D1」）** | `02-menu-open.txt` / `02-menu-dump.txt` / `02-menu-shortcuts.txt` |
| c | 五笔 `wq`+空格 → 你；拼音 `nihao`+空格 → 你好；混输 `kwwl` → 中华人民共和国 | **PASS** | `03-wubi-wq.txt` / `03-pinyin-nihao.txt` / `03-mixed-kwwl.txt` |
| d | `⌘Z` 撤销回上一条 | **PASS** | `04-undo-fresh.txt`（含 `04-undo.txt` 的假阴性说明） |
| e | 四状态往返（中英/全半角/简繁/标点）+ 回读 config | **PASS** | `05-state-language.txt` / `05-state-width.txt` / `05-state-variant.txt` / `05-state-punctuation.txt` |
| f | 模式三循环 mixed→wubi→pinyin→mixed | **PASS** | `06-mode-cycle.txt` / `06-mode-after.txt` |
| g | 设置 / 关于窗口 | **PASS（有差异，见「差异 D2/D3」）** | `07-settings-window.txt` / `07-settings-window-ax.txt` / `07-about-window.txt` / `07-settings-open-commands.txt` / `07-about-retry.txt` |
| h | 还原（mode/标点/字形/输入源） | **PASS** | `08-restore.txt` / `08-textedit-cleanup.txt` |

## b. 菜单（AX 实读）

首次按键激活后 `axmenu open` 报 `desc=萤火虫 items=21`；产品项 7 行（前 4 行是源列表/标题/分隔，后 5 行是系统项），右侧快捷键由 `AXMenuItemCmdChar` + `AXMenuItemCmdModifiers` 直接读出（bit1=⇧、bit3=⌃、bit8=「无 ⌘」，空格键的字符在 macOS 13 上被 AX 报成空串）：

| 菜单行 | AX 标题 | cmdChar | mods | 解码 | 期望（Schema 默认） |
|---|---|---|---|---|---|
| 模式 | 混输模式 | `M` | 13 | ⌃⇧M | `ctrl+shift+m` ✓ |
| 中英 | 中文输入 | 空 | 8 | ⇧（单修饰键，等价字符 `⇧`） | `shift` ✓ |
| 全半角 | 全角输入 | 空（空格） | 13 | ⌃⇧Space | `ctrl+shift+space` ✓ |
| 简繁 | 简体输入 | `T` | 13 | ⌃⇧T | `ctrl+shift+t` ✓ |
| 标点 | 中文标点 | `.` | 13 | ⌃⇧. | `ctrl+shift+.` ✓ |
| 设置 | 设置 | `,` | 12 | ⌃, | `ctrl+,` ✓ |
| 关于 | 关于 | `A` | 13 | ⌃⇧A | `ctrl+shift+a` ✓ |

与 B 的结论一致：菜单只有纯标题 + 真实快捷键列；四状态文案随状态变化（`中文输入`/`英文输入`、`全角输入`/`半角输入`、`简体输入`/`繁体输入`、`中文标点`/`英文标点`）。

## c–d. 输入与撤销

| 操作 | 结果 |
|---|---|
| `wq` + 空格 | 「你」 |
| `nihao` + 空格 | 「你好」 |
| `kwwl`（混输，四码唯一 auto_commit） | 立即上屏「中华人民共和国」 |
| 逐键过程可读性 | 组合中 AX 文本值随候选变化（`w` → `wq`），提交后替换为汉字 |
| `⌘Z` | 撤销最近一次提交（文档由「你好你」回到「你好」） |

**撤销判定的坑（已排除）**：前两次 `⌘Z` 把「清空文档」也回退了（文本由空直接跳回上一次测试的旧内容），原因是 TextEdit 把「程序化清空 + 随后两次 IME 提交」并入了同一个撤销组。改用「⌘A + Delete 清空 → 方向键断开打字组 → 两次提交」后，`⌘Z` 只回退最后一次提交，行为与 B 一致。这是 TextEdit 撤销分组特性，不是输入法缺陷；结论以 `04-undo-fresh.txt` 为准。

## e–f. 四状态与模式

每一项都按「点击 → 读菜单标题 → 读 `config.toml` → 再点击还原 → 再读」执行：

- 中英：`中文输入` ↔ `英文输入`，只影响会话，不写 `config.toml`（符合设计）。
- 全/半角：`全角输入` ↔ `半角输入`，同样为会话级临时切换，配置不变。
- 简/繁：`简体输入` → `繁体输入`（`chinese_variant="traditional"`）→ `简体输入`（`"simplified"`）。
- 标点：`中文标点` → `英文标点`（`punctuation="english"`）→ `中文标点`（`"chinese"`）。
- 模式：点 3 次，`mode` = `wubi` → `pinyin` → `mixed`，菜单标题同步为 `五笔模式`/`拼音模式`/`混输模式`。

全部往返结束后四行文案与 `config.toml` 回到测前状态，配置 SHA 仍为 `48259b19…`。

## g. 设置 / 关于

- 「设置」：命令链路可用，宿主被激活为前台，出现 650×580 面板（`contentRect` 650×500 + 工具栏标题栏），AX 树含工具栏 `输入/候选/快捷键/词库` 与分区控件；点击工具栏「输入」后标题变 `输入 — 萤火虫`、内容切到 `默认输入`（输入模式/输出字形/标点风格/全角 ASCII/五笔与拼音）。见「差异 D2」。
- 「关于」：出现 450×352 窗口，标题 `关于`（含复制诊断/反馈等控件）。见「差异 D3」。
- 面板打开期间点击菜单模式行仍正常（`mixed→wubi→pinyin→mixed` 三循环），说明菜单命令在面板前置时没有被吞。

## 差异与观察

| 编号 | 现象 | 判定 |
|---|---|---|
| **D1** | 菜单产品项为 **7 行**（5 状态 + 设置 + 关于），任务清单/HANDOFF 写的「8 行」与代码契约不符；历史报告 068 的「8 个产品项」对应的是旧构建（含学习区菜单项） | 期望值需订正；本轮按代码契约（`InputStateMenu` 5 项 + 设置 + 关于）判 PASS |
| **D2** | 设置面板**首次打开落在「候选」分区**，标题为 `候选 — 萤火虫`（B 打开即 `输入 — 萤火虫`）；点工具栏「输入」后正常切回，且之后重开保持 `输入` | 与 B 不一致的**平台差异/缺陷候选**（macOS 13.7.8 `NSToolbar` + `.preference` 选中项初始化行为），未定位根因；不影响功能，登记待查 |
| **D3** | 在「刚用 AX 点击过工具栏按钮」之后紧接着点「关于」，有一次没有出现窗口（AX/CG 均无 450×352 窗口）；随后同样的点击连续两次都正常，面板打开时点「关于」也正常 | 疑似探针/AX 点击后的瞬时状态问题，未复现为稳定缺陷；保留证据待观察 |
| **D4** | 菜单项索引与 B 不同：A 上 模式=`[4]`、中英=`[5]`、全半角=`[6]`、简繁=`[7]`、标点=`[8]`、设置=`[10]`、关于=`[11]`（B 的清单是 `[6]`…`[13]`，整体偏移 2，源列表条目数不同） | 平台差异；探针必须先 `dump` 再按索引点击，不能照抄 B 的序号 |
| **D5** | 空格键的 `AXMenuItemCmdChar` 在 macOS 13 上读成空串（`mods=13` 仍证明 ctrl+shift 绑定生效）；`⇧` 单修饰键行同理 | AX 平台差异，不是缺失快捷键 |
| **D6** | 截图取证不可用：本机 `screencapture` 无屏幕录制授权，两次不同画面得到**同一张** 89823 字节静态图（Vision OCR 仅识别出 1 个字符）；已删除无效截图 | 本轮全部结论只依赖 AX/CG/TIS/config 实读，不以离屏图或口头确认为证 |

### 数据变化（如实记录）

- `config.toml`：测前测后 SHA 均为 `48259b19…`，字节级一致。
- 用户词库：测试输入使学习计数写入 1 字节（16553 → 16554 字节，960 行不变，mtime 04:34）。这是产品预期学习行为；按「不创建全量备份」的边界本轮**未回滚**，仅记录。
- 输入源：`com.apple.keylayout.ABC` → `Lampyris.default`（验收所需）→ 还原为 `com.apple.keylayout.ABC`，TIS 回读一致。
- TextEdit：3 个自建文档（`acceptance-a.txt` + 2 个未命名）以「不保存」关闭后退出 TextEdit；未触碰用户文档与真实会话。

## 未覆盖（保持 BLOCKED）

与 B 相同：睡眠/唤醒、多屏与缩放、物理键盘导航、VoiceOver、安全输入框/非 US 布局、客户端矩阵（Safari/Chrome/VSCode/微信/Terminal）、同包性能基线、独立第三方复现、5 工作日试用。另有本轮新增待查：D2（macOS 13 设置面板默认分区）、D3（关于窗口瞬时未出现）。

## 结论

A 机上「同包核心输入（五笔/拼音/混输 auto_commit）+ 撤销 + 四状态往返 + 模式三循环 + 设置/关于窗口 + 菜单快捷键列」全部通过，配置与输入源已还原、宿主未重启、包未被替换。与 B 的三处平台差异（D1 行数口径、D2 设置默认分区、D4 菜单索引）只影响文档与探针口径，D2/D3 登记为待查项；发布门禁中的环境类、无障碍类、客户端类、性能类与流程类仍 BLOCKED。

证据目录（本地，`platforms/macos/build/` 已被 `.gitignore` 忽略，不入库）：`platforms/macos/build/acceptance-a-071/`。
