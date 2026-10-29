# 219 候选窗跟着鼠标而不是输入焦点（build 29 → 30）

> 用户复验 1.0.0/build 29 时报告：**输入框已经获得焦点，但鼠标离得很远时，候选窗出现在鼠标位置**。
> 这是报告 217 §3 定向复验没有覆盖到的场景（那六张截图鼠标都在输入点附近）。

## 1. 根因

`InputController.caretRect()` 调 `StateHUDCaretResolver.resolve(...)` 时传的是：

```swift
startIndex: start, hasText: length > 0, allowsEmptyCaret: false
```

而解析器的第一行是 `guard hasText || allowsEmptyCaret else { return nil }`。
于是只要 **`length() == 0`**（空输入框，或客户端的 `length()` 不把预编辑文本算进去），
解析器立刻返回 `nil`，`caretRect` 直接落到最后一档回退：**鼠标位置**（1×1 点）。

HUD 那条路径一直传的是 `allowsEmptyCaret: true`，所以同样的场景下 HUD 位置是对的、只有候选窗跑偏。
这个差异是 ADR-301 重构前就存在的（旧代码只调一次 `attributes` 也有同类问题），重构时把
`allowsEmptyCaret: false` 原样带了过来。

## 2. 修法

1. **允许空插入点**：候选窗与 HUD 一样传 `allowsEmptyCaret: true`——空输入框的插入点仍然有效。
2. **回退链收敛**：新增 `CaretPlacement.fallback(current:previous:mouse:)`，顺序为
   **本轮解析结果 → 上一次成功的位置 → 鼠标**。鼠标几乎从不是用户想要的位置，只在「本轮失败且
   没有任何历史位置」时使用；每条回退都写 `LAMPYRIS_HUD_DIAG` 原因（`fallback=previous/mouse`）。
3. `lastCaretRect` 只在解析成功时更新，避免把回退值当成历史。

## 3. 验证

| 层 | 内容 |
|---|---|
| 单元 | `caret-placement.swift` 新增回退链三例：本轮结果优先 / 无本轮时用上次位置 / 两者都没有才用鼠标 |
| 解析器 | 既有断言已覆盖「空文档 + `allowsEmptyCaret: true` 取到行框」，本次让候选窗走同一条 |
| 回归 | `make verify`、`make macos-offline-tests`（56 文件 / 303 例）全绿 |
| 实机 | 待用户复验（build 30 已装两台设备）：**聚焦输入框、把鼠标移到屏幕另一端、再打字**，候选窗应贴着插入点 |

## 4. 影响

- 版本仍 1.0.0，构建号 29 → **30**；锁定候选随之更新为 build 30（ZIP `9704f209…`、宿主执行 `16ac739f…`，报告 217 §8）。
- IT-23 尚未开始记第 1 天，因此**不影响**试用基线；两台设备都升级到 30 后再开始计时。
