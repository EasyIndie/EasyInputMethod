# 072 — macOS 13 关于页按钮布局修正（0.1.0 a234ef31 实机反馈）

2026-10-18。用户在 A（Intel / macOS 13.7.8）截取关于页反馈「布局有问题」。本报告给出实测数据、根因与最小修正；**未装包**（实机复验需要新的签名/公证包）。

## 症状（实机，暗色外观）

用户截图 `截屏2026-10-18 08.22.54.png`（窗口 900×704px = 450×352pt）：

- 「复制诊断」与「反馈问题」两个按钮不在同一视觉行上，`反馈问题` 明显偏高；
- 「反馈问题」按钮比文字宽一倍，标题居中偏左、下拉箭头孤零零贴在右端，两个按钮之间看起来空了约 65pt（设计间距 12pt）。

## 实测（AX + 像素，均在已装 0.1.0 宿主 PID 67948 上）

AX 帧（窗口 450×352，内容原点 y=28）：

| 控件 | 位置 | 尺寸 | 行中心 |
|---|---|---|---|
| 复制诊断 | x=96.5, y=229 | 88×32 | midY 245.0 |
| 反馈问题 | x=196.5, y=229 | **157×25** | midY **241.5** |

用户截图里的按钮描边（像素扫描，2x）：

| 控件 | 描边宽度 | 描边纵向范围 |
|---|---|---|
| 复制诊断 | 150px = 75pt | y 599..641 |
| 反馈问题 | **302px = 151pt** | y **591**..633 |

→ 下拉按钮的描边比文字宽一倍，且整体比按钮高 8px（4pt）；OCR 也复现两个标签的顶部相差 12px。

## 根因

1. **`NSPopUpButton.sizeToFit()` 在 macOS 13 上不贴内容**。实测（`/tmp/popup-measure*.swift`）：

   | 标题 | sizeToFit 宽度 | intrinsicContentSize |
   |---|---|---|
   | 反 | 117.0 | 46.0 |
   | 反馈问题 | 157.0 | 86.0 |
   | 反馈问题反馈问题反馈问题 | 263.0 | 192.0 |

   恒定多出 **+71pt**（旧式下拉按钮 chrome 预留）。ADR-198 要求「反馈下拉按钮按标题与系统箭头的实际固有尺寸布局」，代码用 `sizeToFit()`，在新系统上接近固有尺寸所以通过，在 macOS 13 上不成立。

2. **两个控件高度不同却按顶边对齐**。`复制诊断` 是 `NSButton`（rounded/regular，32pt 高），`反馈问题` 是 `NSPopUpButton`（25pt 高）；两者都 `setFrameOrigin(y: 229)`，行中心差 (32−25)/2 = 3.5pt，即实测的 4pt 错位。

3. **既有测试没盯住这两点**：`platforms/macos/tests/tools-presentation.swift` 只断言宽度 `< 120` 与整体水平居中；而该断言在 macOS 13 上其实是**会失败**的（157 > 120），只是 Swift 5.8.1 无法编译该文件（异构字典字面量类型推断，既有问题），所以 A 从来没跑过这套离线断言，缺陷只在 A 的屏幕上暴露。

## 修正（`platforms/macos/Sources/InfoWindow.swift`）

```swift
feedback.addItems(withTitles: ["报告问题", "报告安全漏洞"])
// 旧版 AppKit 的 NSPopUpButton.sizeToFit 会在固有宽度上多加约 71pt（macOS 13 实测），
// 下拉按钮因此比文字宽一倍、箭头离标题很远。按“标题 + 系统箭头”的固有尺寸收窄（ADR-198）。
let natural = feedback.intrinsicContentSize
if natural.width > 0, feedback.frame.width > natural.width + 0.5 {
    feedback.setFrameSize(NSSize(width: natural.width, height: feedback.frame.height))
}
...
// 按钮高 32pt、下拉高 25pt，按行中心对齐，否则两个控件的文字基线相差 3.5pt。
copy.setFrameOrigin(NSPoint(x: start, y: rowTop + (rowHeight - copy.frame.height) / 2))
feedback.setFrameOrigin(
    NSPoint(x: start + copy.frame.width + gap, y: rowTop + (rowHeight - feedback.frame.height) / 2))
```

同时给 `tools-presentation.swift` 加两条断言（`feedback.frame.width <= intrinsic + 1`、两控件 `midY` 差 < 0.5），并把宽度/行中心写进 `LocalAcceptanceEvidence` 的 actual，避免再靠肉眼看截图。

## 验证（本机 A，离屏渲染，不操作桌面）

用与离线套件相同的编译命令（Sources + `libime_ffi.a`，`-warnings-as-errors`）跑离屏测量：

| 外观 | 复制诊断 | 反馈问题 | intrinsic | 行中心差 | 整体居中 | 宽度<120 |
|---|---|---|---|---|---|---|
| 暗色 | 88×32 | **86×25** | 86 | **0.00** | 0.00 | Y |
| 亮色 | 88×32 | 86×25 | 86 | 0.00 | 0.00 | Y |

离屏渲染图（900×648）描边扫描，修正前 → 修正后：

| 控件 | 修正前 | 修正后 |
|---|---|---|
| 复制诊断 | 150px / y599..641 | 150px / y467..509 |
| 反馈问题 | 302px / y591..633 | **160px / y466..508** |

组内总宽 186pt（88+12+86），组中心 225 = 内容中线；两控件描边上下差缩到 1px。

其它门禁：`swiftc -warnings-as-errors` 通过（全部 Sources + 本改动）；`make verify` 全绿（fmt/lint/test/deny/206 产物隐私断言）。

## 未做 / 限制

- **未装包**：`~/Library/Input Methods/Lampyris.app` 仍是 `a234ef31…`，实机画面仍是旧布局；要看到修正必须重新走 `macos-acceptance` 签名/公证并安装（按边界本轮不做热替换）。
- A 的 Swift 5.8.1 编译不了 `tools-presentation.swift`（既有异构字面量问题），离线 Swift 套件在 A 上无法执行；本轮用等价离屏探针取证。建议单开一张卡修这个兼容性，否则 macOS 13 分支的 UI 断言永远跑不到。
- 修正假定 `intrinsicContentSize` 在较新 macOS 上也是「标题 + 箭头」的合理尺寸；CI（较新系统）会跑新增断言，若新系统上 sizeToFit 本来就贴固有尺寸，收窄是空操作。

## 证据

离屏 PNG、帧数据与像素扫描输出保存在本机 `/tmp/aboutprobe2/`（临时目录，不入库）。
