# 081 — B 机安装 `5726556`：两字状态芯片与 HUD 实机验收

2026-10-18。B 机（arm64 / macOS 27）重启（15:48）后全新安装 `5726556`
（zip `8aa59579…`、执行 `0085f2c6…`、Notarized Developer ID），验证 ADR-211 的
候选框内联芯片与 HUD。**本轮发现两个缺陷，已在源码修复，但已装包仍含旧行为，需再出一版包复验。**

## 安装

- 旧包与旧数据移入 `uninstalled/bundle.*`、`uninstalled/data.*`（未删除）。
- 输入源按既有流程在系统设置添加「萤火虫」后 `selsrc` 选中；宿主 PID 3912。
- 新配置为 Schema 默认：`mode=mixed`、`toggle_width=alt+f`、`ctrl+shift` 零残留。

## 通过项

| 项 | 结果 | 证据 |
|---|---|---|
| 菜单快捷键 `⌥M/⇧/⌥F/⌥T/⌥P/⌥,/⌥A` | PASS | `02-menu-shortcuts`（AX: char=F/mods=10） |
| 设置页 8 项显示 `⌥M/⇧/⌥F/⌥P/⌥T/⌥,/⌥A/⌥L` | PASS | `07-settings-shortcuts.txt` |
| 候选窗口芯片（组合态） | PASS | `03-candidate-chips.txt`：`混输 中文 半角 简体 。`，右对齐在翻页按钮左侧 |
| 组合态切换标点：芯片就地更新、候选不消失、无 HUD | PASS | `03-candidate-update.txt`：窗口始终 468×64，仅 `标点：英文标点` 变化 |
| 非组合态切换：HUD 出现并 1.15s 消失 | PASS | `05-hud-width-idle.txt/png`（64×34「半角」）、`05-hud-variant-simplified.png` |
| 学习区不占芯片 | PASS | 组合态仅 5 枚芯片 |

## 发现的缺陷（源码已修）

**D1 组合态切宽度/模式/中英时没有任何反馈。**
`toggleWidth` 先 `cancel()` 组合，但 `showStateFeedback` 仍看到候选窗可见，走进「内联芯片」分支；
随后 `refreshAfterStateChange` 才隐藏候选窗——结果芯片和 HUD 都看不到。
修复：只有 `session.isComposing == true` 且候选窗可见时才内联，否则走 HUD。

**D2 HUD/候选窗定位用的是文档开头，不是插入点。**
`caretRect` 固定 `forCharacterIndex: 0`；空文档/普通输入时 HUD 出现在窗口左上（实测 119,54），
而不是光标处。修复：取 `client.selectedRange().location` 查询光标矩形，失败再退回鼠标位置。

## 还原

输入源 ABC；`mode=mixed`、标点中文、字形简体、半角、学习区关；
`config` SHA `15f49acf…`；执行 SHA 仍 `0085f2c6…`；宿主 3912、窗口 0。

## 下一步

重新出包（含 D1/D2）后按 §4 注销安装，复验：
组合态切宽度应看到 HUD（候选窗关闭）、HUD 出现在真实光标附近；
组合态切标点仍应只更新芯片。

## 本地隔离窗口验收（不装包，2026-10-18 晚）

B 机不空闲、暂不重启，改用 `make macos-dev` 的独立 App（自有 bundle、私有配置、真实 NSPanel）复验 D1/D2：

| 操作 | 结果 |
|---|---|
| 隔离输入区键入 `wq` | 候选窗 468×64，头部实读 `混输 中文 全角 繁体 .`；翻页「上一页」x=765，芯片末端 757，间距 8pt |
| 组合态按 `⌥P` | 候选窗保持 468×64，仅 `标点：英文标点` 就地变化，无 HUD |
| 组合态按 `⌥F` | 组合被取消、候选窗关闭；HUD「全角」64×34 出现在输入区附近 (340,260)，**不再出现在文档左上** |
| 非组合态按 `⌥T` | HUD「繁体」64×34 出现并 1.15s 消失 |
| 退出隔离 App | `PASS interactive cleanup: owned process exited; real files unchanged`（真实 config/词库未被修改） |

证据：`09-isolated-candidate-chips.png`、`09-isolated-hud-variant.png`、`09-isolated-hud-width.png`、`09-isolated-chips.txt`。

为了让这条路径以后也能看到本轮 UI，`Preview` 已同步候选芯片与 HUD（状态变化且未组合时弹 HUD，组合中只更新芯片），仅用于本地隔离验收，不影响安装包。
