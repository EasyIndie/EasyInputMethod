# 085 — 状态提示回到光标跟随（ADR-213）

2026-10-18。用户看过固定位置 HUD 的离屏截图后认为观感不佳，要求回到光标跟随，并与 macOS 输入源提示一致：**不聚焦输入框时不显示**。

## 决定

- 取代 ADR-212：HUD 回到**插入点上方 8pt、水平居中**，按光标所在屏夹取。
- **不再用鼠标兜底**：无客户端、空文档、`attributes` 返回零矩形时不显示。
- 有效性判断允许宽度为 0（插入点矩形常常只有行高）；高度必须 > 0。
- 候选框可见时仍用两字芯片；系统通知仍不用于状态提示。

## 实现

- `StateHUDLayout.isValid(caret:)`：`height > 0`、坐标有限，`width >= 0`。
- `StateHUDLayout.frame(size:caret:visibleFrame:)`：`x = caret.midX - w/2`、`y = caret.maxY + 8`，夹在可见区。
- `StateHUDController.show(_:caret:)`：无效光标直接返回；不再读鼠标。
- `InputController.hudCaretRect()`：取 `selectedRange`（末尾退一格）→ `attributes`；矩形无效返回 nil。
- Preview 同步该行为，便于本地隔离验证。

## 隔离窗口实测

- 鼠标移到 `(1300,800)`，光标在 `(372,570,0,28)`；单 Shift 后 HUD `72×36` 出现在 `(336,258)`：
  水平中心 372、底部 602 ≈ 光标顶部 + 8pt，**与鼠标无关**。
- 首次切换因 Preview 的 `lastFeedback` 尚未初始化而不显示（仅 Preview 问题，真实控制器每次都会调用）。
- 退出隔离 App：`PASS interactive cleanup: owned process exited; real files unchanged`。
- 证据：`platforms/macos/build/acceptance-b-085/caret-hud-isolated.png`。

## 验证

- `candidate.hud-position`：插入点上方 8pt/居中/边界夹取、零矩形与空值不显示、零宽度插入点有效。
- `make verify`、65 场景本地验收、offline 测试全绿。
- 真机需下一版包确认：聚焦输入框才出现、位置贴光标、空文档不出现。
