# 093 — B 机 `17053e1`：头部字号统一 / 芯片与悬停留白

2026-10-18。安装 `17053e1`（zip `02b70dfd…`、执行 `535d546f…`、Notarized Developer ID），
复核报告 092。

## 真机结果（`a` 组合 39 页）

| 元素 | AX frame | 说明 |
|---|---|---|
| 输入码 `a` | (168,123) 222×22 | 12pt monospaced |
| 状态芯片「混输」 | (400,125) 34×18 | 12pt medium，芯片高 20（含背景） |
| 页码 `1/39` | (611,124) 33×17 | 12pt monospacedDigit |
| 上/下一页 | (581/?,121) 26×22 | 12.5pt symbol |
| 首候选「或」 | (168,148) 51×28 | 行高 26 + 悬停留白 |

- 面板 **538×70**（旧 468×68）：芯片字号/留白与候选留白增加后自然变宽变高。
- 头部三块字号统一为 12pt；翻页组保持光学上提 1.5pt（页码中心 132.5、按钮 132，芯片 134）。
- 按钮底 143 → 候选顶 148：5pt。
- 悬停留白由 `PaddedCandidateCell` 横向 6pt、纵向 2pt 实现；离屏 `candidate-pager-*.png` 已含悬停态。

## 还原

输入源 ABC；未改状态，config 尚未生成；执行 SHA `535d546f…`；Finder 激活后候选窗已隐藏。

## 验证

`candidate.status`/`padding` 等 65 场景本地验收、`make verify`、`make macos-offline-tests` 全绿；
`CI` 与 macOS 出包对 `17053e1` 均 **success**。
