# 205 外接屏热插拔后复验落点（pro）；多 Space 切换受阻

## 1. 外接屏热插拔：PASS

用户把 LG 4K（Thunderbolt/DisplayPort→HDMI 链路）**拔掉再插回**，插回后立刻复验。

| 项 | 结果 |
|---|---|
| 显示布局（`screens`） | 与拔插前**完全一致**：内置 `1280×800@2x`（主屏，`0,0`）+ LG `1920×1080@2x`（在**上方**，AppKit `y=800`，AX `y=-1080`） |
| 显示模式 | 内置仍为 `1280×800`（`pixel 2560×1600`，Retina），未被换成 1x |
| `make macos-multi-display` | **4/4 PASS**：内置屏窗口内 `73,166` / 全屏 `56,50`；外接屏窗口内 `73,-914` / 全屏 `13,-1030`，均在各自屏内且贴住文本窗 |
| 证据 | `/tmp/lampyris-multidisplay-replug/`（含每例截图） |

结论：拔插后系统恢回了同一布局、同一缩放，候选窗落点与拔插前一致，没有出现跑到屏外/停在旧坐标的问题。

## 2. 多 Space（非全屏）切换：合成按键切不动 → 改为手动切 + 自动判定

用户已在 Mission Control 里新增桌面，`com.apple.spaces` 显示主屏现有 6 个 Space（`[1, 176, 194, 195, 196, 197]`，当前 `196`），外接屏 1 个（`27`）。

但**用合成按键切换 Space 不生效**，两种通道都试过：

| 方式 | 结果 |
|---|---|
| `keytopid 'ctrl+right'`（CGEvent → HID tap，带 `.maskControl`） | Space 仍是 `196`，前台应用不变 |
| `osascript -e 'tell application "System Events" to key code 124 using control down'` | 同上 |

`defaults read com.apple.symbolichotkeys` 里 79/80（移动左/右一个空间）都是 `enabled = 1`，所以不是开关被关掉；更可能是合成事件不被 Dock 的 Space 切换接受，或本机被其它常驻工具（BetterDisplay 等）接管了该快捷键。

**没有强行替代**：写 `com.apple.spaces` 或用私有 API 切桌面都属于污染系统状态，不做。

**改为手动切 + 自动判定**：请用户手动切桌面后自动复验。

### 2.1 结果（PASS）

用户切到另一个桌面后（`com.apple.spaces`：主屏当前 Space `1`，切前是 `196`），在同一 Space 里新建文本编辑文档并键入 `wq`：

| 项 | 值 |
|---|---|
| 候选窗 | `AXSystemDialog 531×188 @93,186` |
| 所在屏 | 内置主屏 `0,0 1280×800` |
| 判定 | 候选窗完整在屏内（±2px）**PASS**；文本窗 `80,80 920×480`，候选窗在其左上插入点下方 |
| 上屏 | 空格后 `axtext` 读到 `你`（该 Space 里 IME 正常） |
| 证据 | `/tmp/lampyris-space-check/`（`space-candidate.txt`、两张截图） |

收尾：输入源还原 ABC、文档关闭、宿主 PID 69116 未变。

## 3. 结论

- **热插拔**：已关闭（4/4 PASS，布局与缩放未被改动）。
- **多 Space**：已关闭——合成按键切不动 Space 是环境限制（文档记录，不绕路改系统状态），改由用户手动切一次，自动判定候选窗落点 PASS、IME 在该 Space 正常上屏。
- 至此 pro 侧「多屏 / 缩放 / Spaces / 全屏 / 睡眠唤醒 / VoiceOver / 热插拔」全部有结论；剩下的是 **VoiceOver 播报缺口的产品修复（建议 0.1.14）**、过夜/合盖睡眠、以及 IT-15/IT-23 这类需要第三方的项。
