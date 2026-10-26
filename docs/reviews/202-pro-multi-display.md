# 202 多屏 / 缩放 / 全屏下的候选窗落点（pro，外接 4K）

## 1. 背景与硬件

用户 2026-10-26 把外接显示器接到 pro 并要求推进人工项。原先「多屏/缩放/Spaces/全屏」整项都记为人工，本轮把它拆成**可自动化的落点判定**与**只能人判的部分**，先把前者做完。

| 项 | 值 |
|---|---|
| 设备 | pro（Intel x86_64 / macOS 13.7.8 / 用户 `bot`） |
| 内置屏 | Built-in Retina Display，`1280×800` 点 / `2560×1600` 像素（scale 2，主屏） |
| 外接屏 | LG HDR 4K，`1920×1080` 点 / `3840×2160` 像素（scale 2，位于内置屏**上方**） |
| 位形 | 不镜像；两块屏原点分别为 (0,0) 与 (0,800)（AppKit，y 向上） |
| 输入法 | 0.1.13/build 21，执行 SHA `c3b533e4…`（报告201 重装后同一份） |

## 2. 新增探针与脚本

| 文件 | 作用 |
|---|---|
| `tools/macos-probe/screens.swift` | 输出每块屏的 frame/visibleFrame/缩放/是否主屏（坐标基准） |
| `tools/macos-probe/axwins.swift` | 列出指定 App 的 AX 窗口位置/尺寸/角色；macOS 13 的候选窗是 `AXSystemDialog` |
| `tools/macos-probe/cgwins.swift` | CGWindowList 版窗口列表；**无「屏幕录制」授权时为空**，实测这台机器就是空的，所以判定改用 AX |
| `tools/macos-probe/displaymode.swift` | 列/切显示模式；同尺寸优先 HiDPI（`pixelWidth` 更大） |
| `tools/macos-probe/multi-display.sh` | 逐屏 + 全屏各测一次：摆窗口 → guard-focus → 键入 `wq` 触发候选窗 → AX 几何断言 → 截图 |

`make macos-multi-display` 即调用脚本。

**判定规则**（`multi-display.sh`）：候选窗必须 ①完整落在**当前屏**的 AX 矩形内（±2px 容差）、②与文本窗重叠、③贴住文本窗（`|x 差| ≤ 窗宽` 且不高于窗顶）。任一不满足即 FAIL。

## 3. 结果

### 3.1 默认缩放（内置 1280×800@2x）

| 用例 | 结果 |
|---|---|
| 内置屏 · 窗口内 | **PASS** 候选窗 `73,166 531×188`（屏 `0,0 1280×800`） |
| 内置屏 · 全屏 | **PASS** 候选窗 `56,50 531×188` |
| 外接屏 · 窗口内 | **PASS** 候选窗 `73,-914 531×188`（屏 `0,-1080 1920×1080`） |
| 外接屏 · 全屏 | **PASS** 候选窗 `13,-1030 531×188` |

### 3.2 缩放切换到 1440×900「更多空间」（内置屏保持 Retina 2x）

用 `displaymode set 0 1440x900` 切到 `1440×900` 点 / `2880×1800` 像素，重跑同一套：

| 用例 | 结果 |
|---|---|
| 内置屏 · 窗口内 | **PASS** 候选窗 `73,166 531×188`（屏 `0,0 1440×900`） |
| 内置屏 · 全屏 | **PASS** 候选窗 `56,50 531×188` |
| 外接屏 · 窗口内 / 全屏 | **PASS** `73,-914` / `13,-1030` |

随后 `displaymode set 0 1280x800` 还原，`screens` 与起始一致（`1280×800`、scale 2、名称回到 `Built-in Retina Display`）。

**结论**：两块屏、窗口内与全屏、两种缩放比例下，候选窗都紧跟插入点、不越界、不跑屏外。证据（含每例截图）在 `/tmp/lampyris-multidisplay-run9/` 与 `/tmp/lampyris-multidisplay-scaled2/`。

## 4. 过程中发现的真问题

### 4.1 换显示模式/反复全屏后，已运行 App 的 IME 上下文会“变旧”

实测：连续切模式 + 全屏往返若干次后，**文本编辑**里的键入变成裸 ASCII（`axtext` 读到 `wq`、无候选窗、`quality-samples` 报「无法归位到中文态」），而同一时刻探针窗口（`type-session`）仍是正常的 `你你好。`。重启文本编辑即恢复。

这是 App 侧的输入上下文问题（不是宿主崩溃、也不是配置问题），但对用户是可感知的：换分辨率/进出全屏后，个别应用可能需要重开窗口。脚本里已按此处理：**每块屏开始前重置文本编辑、每次断言后清空正文**，之后连跑多次全部 PASS、`quality-samples` 也恢复 16/16。

### 4.2 AX 坐标原点不是包围盒左上角

AX/AppleScript 坐标以**主屏左上角**为原点、y 向下：外接屏在主屏上方时 y 为负（`-1080`）。一开始按「包围盒高度」换算，把内置屏判断成 `y≥1080`，直接误判 FAIL。已修正为「主屏高度 − y − h」。

### 4.3 显示模式 API 的同名陷阱

`CGDisplayCopyAllDisplayModes` 默认不返回 HiDPI 变体；要传 `kCGDisplayShowDuplicateLowResolutionModes` 才能看到 `1280×800@pixel 2560×1600`。第一版按 `width/height` 取第一个匹配，把内置屏从 Retina 切成了 1x（`bounds` 变成 2560×1600），当场按原模式还原并修正选择逻辑（同尺寸取 `pixelWidth` 最大者）。

## 5. 仍然只能人判的部分

- **VoiceOver 实读**：需要听语音，程序只能确认 AX 树暴露了候选与选中项（本报告的 `axwins`/本地验收覆盖了一部分，但不能代替“被朗读”）。
- **物理睡眠/唤醒**：`pmset sleepnow` 只能让机器睡下，唤醒必须由人按键。
- **多 Space（非全屏）切换**：默认 Ctrl+→ 会切换桌面，验证需要人在那个 Space 里操作；本轮覆盖的是全屏（全屏本身就是一个独立 Space）。
- **外接屏热插拔**：拔插显示器时的候选窗重建，需要人在现场观察。

## 6. 复跑方式

```sh
make macos-multi-display                      # 逐屏 + 全屏各一次（约 1 分钟）
./tools/macos-probe/displaymode list          # 看可选模式
./tools/macos-probe/displaymode set 0 1440x900  # 换缩放后再跑一次
./tools/macos-probe/displaymode set 0 1280x800  # 记得还原
```
