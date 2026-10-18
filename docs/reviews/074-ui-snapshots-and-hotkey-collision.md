# 074 — 离屏 UI 截图入口 + ⌃Space 切换后的组合键误判修正

2026-10-18。两件事：新增 `make macos-ui-snapshots`（改 UI 时几秒看效果，不装包）；修正「系统 ⌃Space 切换输入法后，快按 Shift 被当成 ⌃⇧Space 而误切全/半角」。**未装包**。

## A. `make macos-ui-snapshots`

### 是什么

一条命令把 4 类面板离屏渲染成 PNG（亮/暗各一份），并在终端打印帧/留白报告：

| 输出 | 内容 |
|---|---|
| `candidate-single-*.png` | 单页 5 候选（无翻页组） |
| `candidate-pager-*.png` | 5 候选 + `1/55` 翻页组 |
| `candidate-long-*.png` | 7 条超长词（纵排 + 滚动） |
| `candidate-hint-*.png` | 带附行（hint）形态 |
| `about-*.png` | 关于页（真实官方图标） |
| `settings-*.png` | 设置面板（650×500，四分区） |
| `diagnostics-*.png` | 诊断面板（反馈链接） |

- 全部走产品自己的 `renderSnapshotForTesting` / `renderForTesting`，用的是**同一份 Swift 源码**，不是另画一套。
- 私有 `config.toml` 落在 `mktemp` 目录，**不读也不写** `~/Library/Application Support/Lampyris`；不显示窗口、不引用已安装包。
- 每次运行打印行：`candidate-pager-light.png 800×128 面板 400×64 顶/底留白 8/8 行高 24 页码 1/55`，留白/行高可直接对照报告 073 的修正。

### 怎么用

```sh
make macos-ui-snapshots                # 候选 + 关于 + 设置 + 诊断
make macos-ui-snapshots UI=candidate   # 只跑候选窗（少编译一半源码）
OUT=~/Desktop/shots make macos-ui-snapshots
```

### 实测耗时（A：Intel / macOS 13.7.8 / Swift 5.8.1）

| 情形 | 时间 |
|---|---|
| 源码未变（复用缓存二进制） | **5s** |
| 只改候选窗（`UI=candidate` 冷编译 3 个源文件） | **37s** |
| 全量冷编译（8 个源文件，`Settings.swift` 占大头） | 约 110s |

二进制按源码哈希缓存在 `platforms/macos/build/ui-snapshots/.cache/`（已 gitignore），所以「什么都没改」时是秒级；B 机（arm64/macOS 27）应显著更快。

### 边界

- 不含系统输入法菜单（菜单由 AppKit 绘制，无法离屏取得真实渲染），菜单仍按报告 071 的 AX 实读核对。
- 不是验收证据：离屏图不能替代同包实机结论（`docs/开发工作流.md` 的守则不变）。

## B. ⌃Space 切换输入法后的组合键误判

### 现象（用户反馈）

系统用 **⌃Space** 切换输入法到萤火虫后，当前是英文模式，用户很快按一次 **Shift** 想切中文，结果**全/半角被切换了**——被识别成 `⌃⇧Space`。

### 根因

`ConfiguredHotkey.matches` 只比较事件的修饰位与键码。切换输入源时，仍按住的空格事件会被重投递给新激活的输入法，而这时的修饰键已经变成「⌃ 还没松 + 用户又按了 Shift」= `⌃⇧`，于是这个**旧的空格事件**正好命中了 `hotkey.toggle_width = ctrl+shift+space`。

单独 Shift 的判定本来有 `shiftUsedByKey` 保护（`Ctrl+Shift+M` 这类组合不会顺带切中英），但组合键匹配没有「按键必须比修饰键新」的约束。

### 修正（`ImeSession.swift` / `InputController.swift` / `Preview/main.swift`）

`flagsChanged` 时记录时间戳；组合键匹配要求**按键事件晚于最近一次修饰键变化**（20ms 容差，容忍 keyDown 与 flagsChanged 同一物理瞬间的乱序）：

```swift
func matches(_ key: String, _ event: NSEvent) -> Bool {
    guard event.timestamp + Self.chordSettleWindow >= lastModifierChangeAt else { return false }
    return ImeConfig.hotkey(key).matches(event)
}
func noteModifierChange(_ event: NSEvent) { lastModifierChangeAt = event.timestamp }
```

- 被重投递的旧空格事件：时间戳早于 Shift 按下 → 不再触发全/半角。
- 正常的 `⌃⇧Space`（先按修饰键再按空格）：时间戳更新 → 照常生效。
- 单独 Shift 切中英、`⌃⇧M`/`⌃⇧T`/`⌃⇧.`/`⌃,`/`⌃⇧A` 语义不变。

### 验证

等价离屏探针（`ImeSession` + 真实 FFI，合成 `NSEvent`，不注入真实键盘）：

| 用例 | 期望 | 结果 |
|---|---|---|
| 修饰键先到位（t=500.4 空格 / 500.0 变化） | 触发全/半角 | PASS |
| 重投递旧空格（t=699.85 空格 / 700.0 变化） | 不触发、状态不变 | PASS |
| 20ms 容差内乱序（t=899.99 / 900.0） | 仍触发 | PASS |
| 单独 Shift 按下→抬起 | 只切一次中英 | PASS |

同一语义已写进 `platforms/macos/tests/wubi-learning.swift`（`learning.stale-chord`）：`replayedSpace` 必须 `.unmatched` 且状态不变，`settledSpace` 必须 `.handled` 并可复原。

### 剩余风险 / 待决策

- 该保护依赖事件时间戳。若某个系统版本在重投递时**重建**时间戳，误判仍可能出现；到那时需要改成跟踪物理按键按下/抬起（新增 `keyUp` 转发）或直接换默认键。
- `ctrl+shift+space` 本身把 **⌃Space（系统切换输入法）** 包含在内，这是 ADR-208 选定的默认值。若要彻底避免这一类冲突，可把默认改为 `shift+space`（ADR-068 的初心、搜狗/微软惯例）或换掉空格键——属于默认值变更，需先写 ADR 并经你确认，本轮未改。

## 验证与门禁

- `swiftc -warnings-as-errors` 通过（候选/面板两个变体 + `InputController`/`Preview` 语法检查）。
- `make verify` 全绿。
- 真实配置未改动：`config.toml` SHA 仍为 `48259b19…`。
