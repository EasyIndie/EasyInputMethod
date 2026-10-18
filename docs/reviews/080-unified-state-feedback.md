# 080 — 统一输入法状态反馈（光标旁 HUD）

2026-10-18。用户反馈「输入法状态切换时没有可实时感知的途径」，要求设计统一的确认方式。
本轮新增 ADR-211 与 `StateHUD`；**已装 `6494eab` 不含此改动，需下一版包才能在真实 IMK 链路上看到**。

## 设计

| 项 | 决策 |
|---|---|
| 触发 | 中英、全/半角、简/繁、标点、模式、学习区——菜单命令与快捷键共用同一入口 |
| 文案 | `StateFeedback` 单点映射：英文/中文、全角/半角、简体/繁体、中文标点/英文标点、混输/五笔/拼音模式、学习区：开/关 |
| 形态 | 光标上方 8pt 的胶囊：34pt 高、圆角 10、14pt 横向内边距、最小宽 64pt；亮暗自适应、带边框与阴影 |
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

- `make macos-ui-snapshots UI=panels`：新增 `state-hud-{英文,全角,混输模式}-{light,dark}.png` 共 6 张，尺寸 128×68 / 176×68（2x，即 64/88×34pt）。
- `platforms/macos/tests/controller-menu.swift`：新增 6 组文案断言；整套在 `.prohibited` 下编译运行通过（14s），证明无窗口环境不会弹 HUD。
- `make macos-local-acceptance`：62 场景全 PASS（含菜单/设置/候选/学习）。
- `make verify`：全绿。

## 限制与下一步

- 已装包 `6494eab` 不含 `StateHUD`，本轮无法在真实 IMK 上看到浮层；需重新出包后在 B 机验证
  （触发层面已由控制器/菜单测试覆盖，渲染由离屏快照覆盖）。
- 暂不提供关闭开关；若后续需要，新增 `appearance.state_hud` 需单独 ADR。
- 浮层会出现在录屏/截图中，这是预期行为。
