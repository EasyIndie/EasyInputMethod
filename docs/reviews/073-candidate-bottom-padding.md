# 073 — 候选窗漏出的底部留白（翻页区下方空白）修正

2026-10-18。用户对已装 0.1.0（`a234ef31…`）截图反馈「候选框布局有点问题，翻页那块区域间距不太协调」。本报告是实测、根因与修正记录；**未装包**。

## 实测

用户截图 `~/Desktop/截屏2026-10-18 08.38.06.png`（暗色，窗口 398×72pt，页 `1/55`）。按行统计墨迹（阈值 = 背景亮度 + 0.09）：

| 区域 | 像素行 | 相对窗口 |
|---|---|---|
| 窗口内容上下边界 | 46..177 | 0..65.5pt |
| 输入码/页码行墨迹 | 64..89 | 顶部留白 **9pt** |
| 候选行墨迹 | 105..137 | 与上一行间距 8pt |
| 候选行墨迹 → 窗口底 | 137..177 | 底部留白 **20pt** |

也就是说：**顶部 9pt、底部 20pt**，整块内容明显偏上；翻页行被挤在顶边，下方留出一条空带。

离线复现（`CandidateWindow` + 5 候选 + `pageCount=55`，离屏渲染 800×148px）：

| 指标 | 修正前 | 修正后 |
|---|---|---|
| 面板尺寸 | 400×**74** | 400×**64** |
| 页码行上方留白 | 8pt | 8pt |
| 候选行下方留白（frame） | **18pt** | **8pt** |
| 墨迹上下留白 | 12pt / 23pt | 12pt / 13pt |
| 页码/上下页按钮行中心 | 全部 44/54pt 共线 | 不变（共线） |

## 根因

`CandidateWindow.arrange()` 里底部区恒定按「有附行」预留：

```swift
let baseExtra = CGFloat(headerVisible ? 22 : 16) + headerHeight + hintHeight + warningHeight + (headerVisible ? 4 : 0)
```

其中 22 是给 `hint`（18pt）与 8pt 下边距留的位；但宿主 `showCandidates` **从不传 `hint`**（`InputController` 只见 `warning:`），页面也没有真实附行，于是这 18pt 底部区每次都被多留出来：窗口比内容高 18pt，内容整体上移。翻页行又与输入码同处顶部 24pt 表头，看起来就变成「翻页那一行贴着上边、下面空一大块」。

## 修正（`platforms/macos/Sources/CandidateWindow.swift`）

只在真的会显示附行/警告时才保留原来的 22pt 底部区：

```swift
let bottomReserve: CGFloat = (hintHeight + warningHeight) > 0 ? 22 : 12
let baseExtra = CGFloat(headerVisible ? bottomReserve : 16) + headerHeight + hintHeight + warningHeight + (headerVisible ? 4 : 0)
```

结果：无 hint/警告时底部 frame 留白 8pt（与顶部一致），窗口高度 −10pt；有 hint 或繁体警告时高度与布局**与修正前完全相同**（92pt）。学习区（`candidate.show_wubi_learning`）仍按剩余空间排布，只是与候选行的间距从 18pt 收到 10pt。

## 验证（离线，不操作桌面）

- 新增 `candidateViewportFrameForTesting`，并在 `candidate-presentation.swift` 增加不随字体度量漂移的不变式断言：`底部留白 <= 顶部留白 + 2pt`（修正前是 18 vs 8，会直接失败；验证证据写进 `LocalAcceptanceEvidence` 的 `candidate.padding`）。
- 等价离屏探针（Sources + `libime_ffi.a`，`swiftc -warnings-as-errors`）结果：
  - 单页 / 5 行多页 / 30、120 页首末页：`pageFrames` 三者仍共线（midY 相等、按钮高 24），窗口都在给定边界内；
  - 带 hint：92pt（与修正前一致）；带繁体警告：92pt（一致）；
  - 9 条超长词：纵排 + 滚动，300pt 限高内，文本完整。
- `make verify` 全绿。

## 未改动（需要决策）

翻页组本身的间距是现行 ADR-183 的契约：上一页/下一页保留 **24pt 点击区**，与页码各留 4pt frame 间距；因为雪佛龙图形只有约 6pt 宽，视觉上「‹」到「1/55」的空隙约 **17pt**，观感偏松。要收紧到 8–10pt 只能缩点击区或让点击区与页码重叠，属于交互契约变更，**本轮未动**，需先补 ADR 再改。

## 未做 / 限制

- **未装包**：已装 `a234ef31…` 仍是旧布局；实机要看到效果需重新签名/公证出新包。
- A 的 Swift 5.8.1 仍无法编译 `candidate-presentation.swift`（`LocalAcceptanceEvidence` 的异构字典字面量，既有问题），本轮用等价离屏探针取证，新断言由 CI（较新系统）执行。
- 用户截图是暗色外观；亮色未单独截图核对，几何一致（同一套 frame 计算）。

## 证据

`/tmp/candprobe/`（修正前后离屏 PNG、帧与墨迹统计）为临时目录，不入库。
