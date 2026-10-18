# 080 — 统一输入法状态反馈（光标旁 HUD）

2026-10-18。用户反馈「输入法状态切换时没有可实时感知的途径」，要求设计统一的确认方式。
本轮新增 ADR-211 与 `StateHUD`；**已装 `6494eab` 不含此改动，需下一版包才能在真实 IMK 链路上看到**。

## 设计

| 项 | 决策 |
|---|---|
| 触发 | 中英、全/半角、简/繁、标点、模式、学习区——菜单命令与快捷键共用同一入口 |
| 候选态 | 候选框可见时不弹 HUD，改为顶部右侧（翻页区左侧）的两字状态芯片：混输/五笔/拼音、中文/英文、全角/半角、简体/繁体，加 `。`/`.` 标点；学习区不在头部显示（下方学习区本身就是状态）；激活态 accent 底色、默认态次要色 |
| 文案 | `StateFeedback` 单点映射：英文/中文、全角/半角、简体/繁体、中文标点/英文标点、混输/五笔/拼音模式、学习区：开/关 |
| 形态 | 光标上方 8pt 的胶囊：34pt 高、圆角 10、14pt 横向内边距、最小宽 64pt；亮暗自适应、带边框与阴影 |
| 图标 | 采用系统矢量字形（两字芯片 + 标点符号）而非打包 SVG：随字号缩放、自动适配亮暗与高对比，不引入第三方图标资产/许可 |
| 时长 | 1.15s 后 0.18s 淡出；系统「减弱动态效果」时无动画 |
| 定位 | IMK 光标矩形优先；取不到退回鼠标位置；夹在屏幕可见区内 |
| 不打扰 | `NSPanel` + `.nonactivatingPanel`、`ignoresMouseEvents`、不成为 key/main、不写配置、不改会话 |
| 无障碍 | `NSAccessibility` announcement + `staticText` 角色/标签 |
| 测试隔离 | `NSApp.activationPolicy() == .prohibited` 或 `LAMPYRIS_ACCEPTANCE_OUTPUT` 时不创建浮层 |

## 实现

- 新增 `platforms/macos/Sources/StateHUD.swift`：`StateFeedback`、`StateHUDView`、`StateHUDController`。
- `InputController`：四个状态切换方法、`applyInputMode`、以及快捷键路径（模式/学习区）统一调用 `showStateFeedback`。
- 菜单命令与快捷键不各写一套文案；设置页继续显示当前值（面板本身就是状态视图）。

## 验证

- `make macos-ui-snapshots`：HUD 6 张（`state-hud-*`，修好暗色背景）；候选窗四形态截图带状态芯片（`candidate-*-*.png`），终端打印 `状态 混 英 全 简 .` 等。
- 暗色回归：`candidate.hud` 断言同一 HUD 在亮/暗下背景亮度差 > 0.3（修复前暗色套用亮色背景）。
- `platforms/macos/tests/controller-menu.swift`：新增 6 组文案断言；整套在 `.prohibited` 下编译运行通过（14s），证明无窗口环境不会弹 HUD。
- `make macos-local-acceptance`：**64 场景全 PASS**（新增 `candidate.status` 两字芯片布局与 `candidate.hud` 亮暗断言）。
- `make verify`：全绿。

## 限制与下一步

- 已装包 `6494eab` 不含 `StateHUD`，本轮无法在真实 IMK 上看到浮层；需重新出包后在 B 机验证
  （触发层面已由控制器/菜单测试覆盖，渲染由离屏快照覆盖）。
- 暂不提供关闭开关；若后续需要，新增 `appearance.state_hud` 需单独 ADR。
- 浮层会出现在录屏/截图中，这是预期行为。

## 后续（ADR-212）

实机发现 `attributes(forCharacterIndex:)` 在空行/末尾不可靠，HUD 跟随光标会落在不可预测的位置；先改为固定屏幕顶部居中（ADR-212），随后按用户反馈改为「光标跟随、无焦点不显示」（ADR-213）。详见报告 084/085。
