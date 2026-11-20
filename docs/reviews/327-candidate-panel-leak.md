# 327 — 候选窗残留（幽灵面板）：根因与修复

> 背景：2026-11-20 11:30 air 真机（装 1.3.2 / 45）出现一次「桌面残留候选窗」：面板以 `.popUpMenu` 层永久浮着，
> 显示 `完整码 KHK / 识别码 竖·杂合结构`，点击、切输入源、宿主失焦都不消失；`kill` 宿主进程后立即消失。
> 本报告记录取证、根因判断、修复的三层兜底与验证。

## 1. 现场取证

| 项 | 值 |
|---|---|
| 窗口 | owner `萤火虫`，`CGWindowLayer = 101`（`NSWindow.Level.popUpMenu`），`window# 25296`，bounds `{361,345,538,182}` |
| 进程 | `pid 40910`，`STAT S`、`%CPU 0.0` —— **没有卡死**，只是没人叫它收窗 |
| 恢复 | `kill 40910` → 窗口即刻消失；输入源切回后由 `imklaunchagent` 自动拉起宿主，不需要重装 |

## 2. 为什么"漏一个 `hide()` 就永久浮着"

候选面板的四个属性都是**必须的**，但组合起来把容错度降到零：

| 属性 | 为什么需要 | 副作用 |
|---|---|---|
| `hidesOnDeactivate = false` | IMK 宿主长期不是 active app，若为 true 面板一显示就自己消失 | 宿主失活不会自动收窗 |
| `level = .popUpMenu` | 要盖住宿主窗口与菜单 | 永久在最上层，用户点不到"关闭" |
| `canJoinAllSpaces` | 切换桌面时跟随 | 每个桌面都能看到它 |
| `stationary` | 不随窗口拖动 | 位置固定，更显眼 |

而唯一的收窗入口是 `CandidateWindow.hide()`。只要有一条路径"内容还在、窗口可见、但没人调 `hide()`"，
面板就会一直挂着——而 0.2 s 的主题定时器当时只做 `refreshAppearance()`，**没有任何自查**。

## 3. 修复：三层彼此冗余的兜底

改动集中在 `platforms/macos/Sources/CandidateWindow.swift` 与 `InputController.swift`。

### 3.1 不变量定义（CandidateWindow）

> **可见的候选窗必须有内容。**

```swift
@discardableResult
func enforceVisibilityInvariant() -> Bool {
    guard panel.isVisible, renderedCount == 0 else { return false }
    themeTimer?.invalidate(); themeTimer = nil
    panel.orderOut(nil)
    visibilityInvariantHideCount += 1   // 现场取证/测试用，正常输入路径应为 0
    return true
}
```

三条独立入口，任一条成立就不会漏：

| # | 位置 | 触发时机 | 覆盖的漏法 |
|---|---|---|---|
| 1 | `show(at:)` 开头 | 每次要显示时 | 空面板被 `orderFront` —— 幽灵窗口根本没有内容可显示 |
| 2 | `update(candidates:)` 末尾（`candidates.isEmpty`） | 每次内容清空 | 清空后忘了 `hide()` |
| 3 | `themeTimer` 每 0.2 s tick | **没有任何后续调用时也会跑** | 最后一条防线：无人调用、无按键、无焦点变化 |

第 3 条是关键：定时器只在面板可见期间存在（`show()` 启动、`hide()` 停掉），所以它既是"可见期间的自查心跳"，
又不会在隐藏后空转。

### 3.2 控制器侧兜底（InputController）

- `hideCandidateWindowIfIdle()`：**每个键盘事件开头**执行；条件为「面板可见 && 没有符号面板 && `session?.isComposing != true`」。
  用 `!= true` 而非 `== false`：拿不到会话时同样收窗（宁可少显示，不留浮窗）。
- `deactivateServer` 在 `finishComposition` 之后**无条件**再 `candidateWindow?.hide()`——失活是最该收窗的时刻，
  不依赖 `finishComposition` 内部分支是否走到。

### 3.3 明确不做

- **不改 `hidesOnDeactivate`**：改成 `true` 会让面板在 IMK 这种"长期非 active"的进程里一显示就消失。
- **不加周期性强制 `orderOut`**：那会把"可见"变成概率事件，反而掩盖真实回归；不变量只看**内容是否为空**。

## 4. 验证

### 4.1 窗口级回归（`platforms/macos/tests/candidate-presentation.swift`，用例 `candidate.visibility-invariant`）

| 断言 | 结果 |
|---|---|
| `show()` 之后 `isVisible` | PASS |
| `update(candidates: [])` 后面板必须不可见（不变量 2） | PASS |
| 有内容时 `enforceVisibilityInvariant()` 不误收，返回 false | PASS |
| 空内容再 `show()` 是空操作（不变量 1） | PASS |
| 一轮泄漏只计一次（`visibilityInvariantHideCount` +1） | PASS |

### 4.2 现场对照（真机，装的是未修复的 1.3.2）

用探针驱动真实 IMK 复现"组合态"：

```
type-session.sh 'khk' --settle 15   # 同时每 0.9 s 采一次 cgwins
t=3 {"layer":101,"owner":"萤火虫","bounds":[245,543,504,182]}
```

组合态期间面板按预期是 `layer 101`（正常）。随后 `kill -9` 掉测试客户端窗口（模拟"宿主窗口在组合态中消失"），
`cgwins 萤火虫` 回到 `{"windows":[]}` —— 这条路径由系统 `deactivate` 兜住了，**不是这次的漏点**；
原始幽灵面板的复现路径仍未拿到（用户侧是长时间使用后偶发）。

### 4.3 自动化

- `make macos-offline-tests`：**72 文件 / 360 例全绿**（含 `candidate-presentation` 全套）
- `make verify`：810 产物、0 网络符号
- `build.sh --strict`：通过

## 5. 状态与后续

- **状态**：已修复（代码 + 回归用例），随下一个候选包发版；本报告与 `docs/待办与积压.md` P1-W1 同步记录
  「已修复 / 待复现验证」。
- **还缺什么**：一次"长久使用后仍然没有 layer 101 残留"的实机观察。建议在 1.3.3 候选装好后，
  正常用一段时间再跑 `tools/macos-probe/bin/cgwins 萤火虫`，期望**空结果**；若仍有残留，
  看 `visibilityInvariantHideCount`（可从 `PerfTrace` 或一次性日志导出）判断是哪一层没生效。
- **不要**因为这次修复就把 `hidesOnDeactivate` 打开，也不要给面板加"多久没动就自己关"的超时——
  那会把真实状态机的问题变成时间竞猜。
