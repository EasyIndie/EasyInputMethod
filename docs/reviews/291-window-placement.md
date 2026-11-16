# 291 — 自建窗口落点：鼠标所在屏优先 + 可见区域夹取

日期：2026-11-16　设备：air（arm64 / macOS 27.2，主屏 1440×900 + 副屏 1920×1080 位于上方）
结论：**隔离预览实机 PASS**；尚未进入已装包（等下一次公证候选换包时一并复验）。

## 1. 起因

报告 290 的已装包复验里，练习与使用指南窗口打开后落在副屏（AX 坐标 `y=-912` / `y=-879`），
从主屏看像"窗口没打开"。根因是 `NSWindow.center()` 只按窗口当前屏（新建时按主屏）居中，
不感知鼠标/实际可见区域。

## 2. 改动（ADR-365）

| 文件 | 内容 |
|---|---|
| `WindowPlacement.swift`（新增） | `screenIndex(mouse:frames:)` 选屏 → `origin(size:visible:)` 居中并夹取 → `place(_:)` 应用到窗口 |
| `PracticeWindow` / `OnboardingWindow` / `Settings` / `PassageWindow` | 去掉各自的 `center()`，显示时统一 `WindowPlacement.place(window)` |
| `wubi-learning.swift` | 新增纯函数断言：鼠标在主屏/副屏/nil、主屏居中、副屏落点在可见区域内、超大窗口贴左上 |

## 3. 验证

| 门禁 | 结果 |
|---|---|
| `make verify` | PASS（542 产物零网络符号） |
| 离线回归（含新增断言） | **68 文件 / 337 例 PASS** |
| `build.sh --strict` | PASS |
| 隔离预览实机（鼠标在主屏 403,106） | 练习窗口 `(360,215)`；指南步 1 `(410,339)`、步 2 `620×264` 仍在主屏内；设置 `(395,171,650×588)`；会话 `PASS interactive cleanup … real files unchanged`，输入源还原 |

## 4. 差异与遗留

- 未在已装包验证：本机只能构建 ad-hoc 包；该改动随下一次 `dev → main` 的公证候选换包时复验
  （打开练习/指南/设置，确认落在鼠标所在屏且整窗可见）。
- 不记忆窗口位置、不改窗口尺寸策略；点开菜单时鼠标在副屏，窗口就落在副屏（预期行为）。
