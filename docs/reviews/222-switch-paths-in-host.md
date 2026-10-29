# 222 组合态切换：核心改对了，但宿主两条路径没走到（build 32 → 33）

> 承接报告 [221](221-switch-keeps-composition.md)。build 32 装机复验：**⌥F 通过，Shift 与 ⌥M 仍丢字**。
> 本报告记录这两条为什么没被上一版修到，以及修法与最终复验。

## 1. 为什么 build 32 只修好了 ⌥F

| 快捷键 | 实际入口 | build 32 改在哪 | 结果 |
|---|---|---|---|
| ⌥F | `toggleWidth()` → `session.toggleWidth()` → `refreshAfterStateChange()` | **核心** `Session::toggle_width`（去掉 `cancel()`） | ✅ 生效 |
| Shift | `handle(_:)` 的 `.flagsChanged` 分支 → `session.shiftTransition(...)` → `clearMarked` + `hide()` | 宿主的 `toggleEnglish(_:)`（**菜单/快捷键**入口） | ❌ 键盘走不到 |
| ⌥M | `applyInputMode()` → **先** `cancelClientComposition()` **再** `setMode()` | 核心 `Session::set_mode`（保留组合） | ❌ 取消发生在调用核心之前 |

两条都不是「改错了」，而是**改在了另一条等价入口上**——截图/探针都看不出来，只有真机按键能暴露。

## 2. 修法（build 33）

**Shift**：在 `shiftTransition` 之前把编码取出来（它内部会 `cancel()`），切换后 `clearMarked` + `insertText(raw)`：

```swift
let pendingRaw = session.isComposing && !session.isEnglish ? session.buffer : nil
let toggled = session.shiftTransition(isDown: flags.contains(.shift), otherModifier: other)
if toggled {
    if let client { clearMarked(client) }
    if let raw = pendingRaw, !raw.isEmpty, let client { client.insertText(raw, ...) }
    candidateWindow?.hide()
    showStateFeedback(StateFeedback.language(session.isEnglish))
}
```

**⌥M**：去掉 `applyInputMode()` 里的 `cancelClientComposition()`，改为

```swift
session?.setMode(next)          // 核心保留缓冲区并按新模式重算
showStateFeedback(StateFeedback.mode(next))
refreshAfterStateChange()       // 预编辑与候选跟上新模式
```

## 3. 验证

| 项 | 结果 |
|---|---|
| `test-controller-menu`（真实 IMK 派发探针） | PASS |
| `make verify` | PASS |
| `make macos-offline-tests` | 56 文件 / 303 例 PASS |
| **实机（build 33，用户）** | ① 打字出候选 → Shift：文档落下 `nihao` 字母并切英文 **PASS**；② 打字出候选 → ⌥M：候选框不消失、候选按新模式刷新 **PASS**；③ ⌥F 保持 PASS |

## 4. 教训

1. **同一个动作常有多个入口**（键盘 / 菜单 / 快捷键 / 探针），改行为时要先把入口列全再动手；本次 `toggleEnglish` 有两条，`setMode` 有三个调用点。
2 这两条路径属 AppKit 事件处理，**离线探针覆盖不到**，必须装机按键复验——build 32 的"已改完"结论下得太早。
3. 已在 `iterate-macos-ime` 的收尾清单里强调：换包后先确认跑的是新二进制（报告 220），再做行为判断。
