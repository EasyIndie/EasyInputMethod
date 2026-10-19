# 096 — Finder 搜索框获焦时 HUD 不显示（报告 095 的回归）

2026-10-19，用户实测：**Finder 打开后，搜索框获焦，切换状态时没有 HUD**。

## 根因

报告 095 为了修 D7（Finder 桌面误显示），用了「`bundleIdentifier() == "com.apple.finder"` 且 `length()==0` 就不显示」的一刀切规则。
Finder 的**搜索框也是 Finder 的文本客户端**，且空搜索框 `length()==0` → 被这条规则误杀。

## 修法（ADR-214 修订）

用**窗口层**区分“桌面伪光标”和“真输入框”：

- `client.windowLevel() < 0` → 桌面/图标视图这类桌面层窗口，`length()==0` 时不算有效光标（不显示）；
- `windowLevel() >= 0`（普通窗口：Finder 搜索框、TextEdit、终端…）→ 空内容也允许显示。

同时保留：客户端必须属于前台应用、光标中心必须在屏内、`attributes` 两趟回退后再退 `firstRect`。
诊断日志新增 `level=` 字段，便于真机核对。

## 验收清单（待新包）

| 场景 | 期望 |
|---|---|
| Finder 桌面获焦（点桌面空白处） | 不显示 HUD |
| **Finder 搜索框获焦（空）** | **显示 HUD** |
| Finder 搜索框有文字 | 显示 HUD |
| TextEdit 空文档 / 文末 | 显示，上方 8pt |
| Terminal 有焦点光标 | 显示 |
