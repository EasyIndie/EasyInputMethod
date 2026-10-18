# 084 — 状态提示改为固定位置（调研与实现）

> **已被 ADR-213 取代（同日）**：用户看离屏截图后认为固定位置观感不佳，改回光标跟随；无焦点/无有效光标时不显示。见报告 085。

2026-10-18。报告 083 证明 HUD 跟随光标在空行/末尾不可靠；用户要求调研其它输入法并给出固定位置的方案。

## 调研

| 来源 | 做法 | 结论 |
|---|---|---|
| macOS 自带输入源提示 | Sonoma 后靠近光标的小图标；不聚焦输入框时可能不显示 | 光标锚点不可靠 |
| [LnHud](https://lnhud.zerolive.co.kr/en) | 默认**屏幕居中**，可选 9 宫格位置、显示器、0.5–3s、字号 10–96pt；理由是菜单栏角落易错过、全屏时不可见 | 固定位置 + 多屏选择是成熟做法 |
| [LangBanner](https://github.com/Kovalsky/lang-banner) | 在**当前工作显示器居中**显示大号 HUD，focused/mouse/main 三种屏幕选择，无辅助功能权限 | 固定位置可行且不需要 AX |
| Fcitx5 OSD | 独立的屏幕 overlay，切换输入法时提示 | 跨平台一致的需求 |
| `UNUserNotification` | 需授权、受专注模式/通知中心排队影响、不能自定义位置与时长、会堆积通知历史 | **不适合高频状态切换** |

## 决定（ADR-212）

- HUD 改为**固定位置**：鼠标所在显示器的可见区域**顶部居中**，距菜单栏下 16pt；找不到鼠标所在屏则退回主屏。
- 仍为非激活、点击穿透面板，跨 Space/全屏；1.15s 淡出，遵循减弱动态效果，VoiceOver 播报。
- 候选框可见时继续用内联芯片，不弹 HUD。
- 不用系统通知做状态提示；通知只留给错误/一次性事项。
- 光标矩形只保留给候选窗定位。

## 实现

- `StateHUDLayout.frame(size:visibleFrame:)`：`x = midX - w/2`、`y = maxY - h - 16`。
- `StateHUDLayout.screenIndex(mouse:among:)`：取包含鼠标的屏幕，找不到回主屏。
- `StateHUDController.show(_:)` 不再接收 caret；尺寸微调为 36pt 高、15.5pt 字、16pt 内边距、最小宽 72pt。
- `collectionBehavior` 增加 `.fullScreenAuxiliary`。

## 验证

- `candidate.hud-position`：断言顶部居中、距顶 16pt、尺寸，以及鼠标在第一/第二屏时的选择（65 场景本地验收）。
- `candidate.hud`：亮/暗背景亮度差继续通过。
- `make macos-ui-snapshots` 重新生成 HUD 图片；`make verify`、offline、preview smoke 全绿。
- 真机需在下一版包确认：HUD 始终出现在当前屏幕顶部居中，与光标/空行无关。

## 取舍

提示离光标较远，需要抬眼看一次；换来的是 100% 可预测的位置。后续可加 `appearance.state_hud_position`（center/corner）配置，需另开 ADR。

## 隔离窗口实测（不装包）

`make macos-dev` 独立窗口，鼠标移到 `(1300,800)`，用单 Shift 触发状态变化：

- HUD 窗口 `72×36`，位置 `(684,46)`（1440 宽屏的水平中心，距顶 46pt），**与鼠标/光标无关**；
- 文案 `英文` / `中文` 正确切换；
- 退出隔离 App：`PASS interactive cleanup: owned process exited; real files unchanged`。
- 证据：`platforms/macos/build/acceptance-b-084/fixed-hud-isolated.png`。

> 隔离 Preview 里 `⌥T` 等组合会被菜单 keyEquivalent 先截获，不走 `keyDown`，因此 HUD 复验用单 Shift；
> 真实 IMK 宿主里组合键由 `InputController` 统一处理，不受此限制。
