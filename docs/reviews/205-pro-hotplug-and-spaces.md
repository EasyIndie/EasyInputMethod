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

## 2. 多 Space（非全屏）切换：暂受阻

用户已在 Mission Control 里新增桌面，`com.apple.spaces` 显示主屏现有 6 个 Space（`[1, 176, 194, 195, 196, 197]`，当前 `196`），外接屏 1 个（`27`）。

但**用合成按键切换 Space 不生效**，两种通道都试过：

| 方式 | 结果 |
|---|---|
| `keytopid 'ctrl+right'`（CGEvent → HID tap，带 `.maskControl`） | Space 仍是 `196`，前台应用不变 |
| `osascript -e 'tell application "System Events" to key code 124 using control down'` | 同上 |

`defaults read com.apple.symbolichotkeys` 里 79/80（移动左/右一个空间）都是 `enabled = 1`，所以不是开关被关掉；更可能是合成事件不被 Dock 的 Space 切换接受，或本机被其它常驻工具（BetterDisplay 等）接管了该快捷键。

**没有强行替代**：写 `com.apple.spaces` 或用私有 API 切桌面都属于污染系统状态，不做。

**下一步（需用户手动一步）**：用户在键盘上按一下切换桌面（或 Mission Control 点另一个桌面），我随后在新的 Space 里新建文档、键入 `wq`，用 `axwins` 断言候选窗仍落在当前屏内、贴住插入点；再切回原桌面。

## 3. 结论

- 热插拔这条**已关闭**（4/4 PASS，布局与缩放未被改动）。
- 多 Space 的**候选窗落点判定脚本已就绪**（`multi-display.sh` 的同一套断言），只差用户在目标 Space 里手动切一次桌面。
