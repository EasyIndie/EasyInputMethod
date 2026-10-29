# 223 候选窗去掉「中文/英文」芯片（ADR-303）

> 用户观察：候选框出现时中英状态始终显示「中文」，而按 Shift 切英文时候选框直接消失——
> 那么这枚芯片就恒为「中文」，属于多余信息。要求确认后取消，以节省候选框空间。

## 1. 确认：这是结构性的，不是显示 bug

| 证据 | 结论 |
|---|---|
| `Session::handle_key` 首行 `if self.english { commit; return }` | 英文模式每键立即上屏，**不建缓冲区** |
| `Session::composing()` 仅在 `handle_key` 的非英文分支置真 | 英文模式下永远 false |
| `InputController.showCandidates` 只在 `isComposing` 分支被调用 | 候选窗**不可能**在英文态出现 |
| ADR-302 后 Shift 切英文会先提交编码再切 | 切换瞬间组合即结束，窗口随之隐藏 |

即：**候选窗可见 ⇒ 一定处于中文输入**，芯片恒为「中文」。

## 2. 改动

- `CandidateStatus.chips`：5 枚 → 4 枚（模式 / 全半角 / 简繁 / 标点）
- `CandidateStatus.english` 字段删除；`accessibilityLabel` 去掉「语言：」分支
- 构造点同步：`InputController.candidateStatus()`、`Preview/main.swift`
- 断言同步：`candidate-presentation`（两次芯片列表断言 + 文案）、`ui-snapshots` 4 处

## 3. 验证

- `make macos-offline-tests`：56 文件 / 303 例 PASS
- 实机（build 34）：待用户确认外观

## 4. 不丢的信息

- 中英切换时弹 HUD（约 1.15 秒），VoiceOver 仍通过 `StateFeedback.language` 播报「语言：中文/英文」
- 模式 / 全半角 / 简繁 / 标点仍有芯片内联反馈
