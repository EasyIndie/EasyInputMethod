# 082 — B 机 `9f64719` 真机复验：芯片与 D1/D2

2026-10-18。B 机重启（16:35）后全新安装 `9f64719`（zip `c310ea15…`、执行 `3bc41a86…`、
Notarized Developer ID），复验报告 081 的 D1/D2 与两字芯片。

## 通过

| 项 | 结果 | 证据 |
|---|---|---|
| 菜单/设置快捷键 `⌥F` | PASS | `precondition.txt`、设置页实读 |
| 组合态芯片 | PASS | `03-chips-default.txt`：`混输 中文 半角 简体 。` |
| 组合态 `⌥P` | PASS | `03-chips-punctuation.txt`：候选保持 468×64，只更新 `标点：英文标点`，无 HUD |
| 组合态 `⌥F`（D1） | PASS | `05-hud-width.txt`：候选关闭，HUD「全角」出现（不再「什么都不显示」） |
| 非组合态 HUD | PASS | `05-hud-variant-real.png`、`05-hud-variant-caret.png` |
| 还原 | PASS | ABC、`mode=mixed`、标点中文、简体、半角；`config` SHA `15f49acf…` |

## 新发现（已修，待下一包复验）

**D2 的剩余部分：光标在文本末尾时取不到矩形。**
`attributes(forCharacterIndex:)` 在 `location == length`（最常见的光标位置）返回空矩形，
所以 HUD 仍可能退化到 IMK 给出的窗口边缘/鼠标位置（实测空文档 119,54）。
修复：`caretLookupIndex(selectionLocation:length:)` 在非空文本里退一格取最后一个字符，
空文档仍回退原逻辑；已由 `controller-menu` 单测覆盖（首/中/末/未知选区）。
该修复在**下一个包**中，安装后需再看一次「有文字时 HUD 是否贴着光标」。

## 状态

已装包 `9f64719` 保留；输入源 ABC；`config` SHA `15f49acf…`；宿主 1858 常驻、窗口 0。
