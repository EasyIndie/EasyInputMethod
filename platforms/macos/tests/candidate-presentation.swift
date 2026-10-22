import Cocoa
import ime

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else { fail("private config") }
let paddedCell = PaddedCandidateCell(textCell: "")
for width: CGFloat in [0, 1, 11, 12, 64] {
    for height: CGFloat in [0, 1, 3, 4, 26] {
        let bounds = NSRect(x: 7, y: 11, width: width, height: height)
        let drawing = paddedCell.drawingRect(forBounds: bounds)
        guard [drawing.minX, drawing.minY, drawing.width, drawing.height].allSatisfy(\.isFinite),
              drawing.width >= 0, drawing.height >= 0,
              drawing.minX >= bounds.minX, drawing.maxX <= bounds.maxX,
              drawing.minY >= bounds.minY, drawing.maxY <= bounds.maxY
        else { fail("padding must remain finite inside small bounds") }
    }
}
guard paddedCell.drawingRect(forBounds: .null) == .zero else { fail("invalid padding bounds") }
guard paddedCell.drawingRect(forBounds: NSRect(x: 7, y: 11, width: 64, height: 26))
        == NSRect(x: 13, y: 13, width: 52, height: 22)
else { fail("normal candidate padding unchanged") }
let window = CandidateWindow()
let caret = NSRect(x: 16, y: 20, width: 2, height: 20)
let area = NSRect(x: 0, y: 0, width: 320, height: 300)
let values = [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
              ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false)]
window.update(candidates: values, input: "wq", hint: "键位提示：W 人 · Q 金")
window.layout(at: caret, within: area)
guard !window.permitsKeyboardFocusForTesting, area.contains(window.frame),
      window.displayedCandidateTexts == ["1 你", "2 尼"],
      window.displayedInput == "wq", !window.pageStateForTesting.visible,
      window.candidateAccessibilityLabelsForTesting[0].contains("五笔"),
      window.candidateAccessibilityLabelsForTesting[1].contains("拼"),
      window.candidateFontForTesting(at: 0)?.pointSize == 17,
      window.candidateFontForTesting(at: 0) != window.candidateFontForTesting(at: 1)
else { fail("minimal body/source accessibility/font/focus") }
// Hover must not create a second filled selection beside keyboard focus.
for appearance in [NSAppearance.Name.aqua, .darkAqua] {
    let focused = CandidateLabel(labelWithString: "1 你")
    let hovered = CandidateLabel(labelWithString: "2 像")
    focused.appearance = NSAppearance(named: appearance)
    hovered.appearance = NSAppearance(named: appearance)
    focused.setKeyboardSelected(true)
    hovered.setHovered(true)
    guard (focused.layer?.backgroundColor?.alpha ?? 0) > 0,
          (hovered.layer?.backgroundColor?.alpha ?? 0) == 0,
          (hovered.layer?.borderWidth ?? 0) > 0
    else { fail("hover must not duplicate filled keyboard focus") }
    hovered.setKeyboardSelected(true)
    focused.setKeyboardSelected(false)
    guard (focused.layer?.backgroundColor?.alpha ?? 0) == 0,
          (hovered.layer?.backgroundColor?.alpha ?? 0) > 0,
          hovered.layer?.borderWidth == 0
    else { fail("focused hover uses one filled selection") }
    hovered.setKeyboardSelected(false)
    hovered.setHovered(false)
    guard hovered.layer?.borderWidth == 0,
          (hovered.layer?.backgroundColor?.alpha ?? 0) == 0
    else { fail("hover reuse clears decoration") }
}
var navigation = CandidateSelectionState()
guard navigation.move(1, count: 2) == 1,
      navigation.move(1, count: 2) == 1,
      navigation.move(-1, count: 2) == 0,
      navigation.move(-1, count: 2) == 0,
      navigation.move(1, count: 0) == nil, navigation.index == 0
else { fail("candidate navigation bounds/reset") }
window.update(candidates: values, selectedIndex: 1, input: "wq")
window.layout(at: caret, within: area)
guard window.selectedCandidateIndexForTesting == 1,
      window.keyboardSelectedCandidatesForTesting == [1],
      window.candidateAccessibilityLabelsForTesting[1].contains("键盘焦点")
else { fail("keyboard focus presentation/accessibility") }
let anchoredSize = window.frame.size
let anchoredGeometry = window.layoutForTesting()!
let sameSizeFrame = window.frame
window.update(candidates: values, selectedIndex: 1, input: "wq")
window.layout(at: caret, within: area)
guard window.frame == sameSizeFrame,
      window.layoutForTesting()!.labels == anchoredGeometry.labels,
      window.selectedCandidateIndexForTesting == 1,
      window.displayedCandidateTexts.count == values.count
else { fail("same-size refresh preserves geometry and selection") }
let movedCaret = NSRect(x: 48, y: 70, width: 2, height: 20)
window.layout(at: movedCaret, within: area)
guard window.frame.origin != NSPoint(x: caret.minX, y: caret.maxY + 4),
      window.frame.size == anchoredSize,
      window.layoutForTesting()!.labels == anchoredGeometry.labels,
      window.selectedCandidateIndexForTesting == 1,
      area.contains(window.frame)
else { fail("same-size caret move preserves candidate geometry and focus") }
let shiftedArea = area.offsetBy(dx: 800, dy: 100)
window.layout(at: movedCaret.offsetBy(dx: 800, dy: 100), within: shiftedArea)
guard shiftedArea.contains(window.frame), window.frame.size == anchoredSize,
      window.selectedCandidateIndexForTesting == 1
else { fail("same-size screen-origin change repositions candidates") }
// Reflow the same selected candidates; navigation and hints must follow rendered geometry.
for width: CGFloat in [320, 90, 320] {
    window.update(candidates: values, selectedIndex: 1, input: "wq", showsNavigationHint: true)
    window.layout(at: caret, within: NSRect(x: 0, y: 0, width: width, height: 500))
    let vertical = width == 90
    guard window.isVertical == vertical,
          window.selectedCandidateIndexForTesting == 1,
          window.displayedHintForTesting.hasPrefix(vertical ? "↑↓" : "←→"),
          let geometry = window.layoutForTesting(), geometry.labels.count == 2,
          vertical ? geometry.labels[0].minY > geometry.labels[1].minY
                   : geometry.labels[0].minX < geometry.labels[1].minX
    else { fail("reflow axis/hint/focus/geometry") }
    for key: UInt16 in [123, 124, 125, 126] {
        for flags: NSEvent.ModifierFlags in [[], .shift, .command, .control, .option] {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1f}", charactersIgnoringModifiers: "\u{1f}",
                isARepeat: true, keyCode: key) else { fail("axis event") }
            let expected: Int? = flags.intersection([.command, .control, .option]).isEmpty
                ? (key == (vertical ? 126 : 123) ? -1 : key == (vertical ? 125 : 124) ? 1 : nil)
                : nil
            guard window.navigationDelta(for: event) == expected else { fail("layout navigation mapping") }
        }
    }
}
guard let selectedSnapshot = window.renderSnapshotForTesting(), selectedSnapshot.pixelsWide > 0 else {
    fail("keyboard focus snapshot")
}
if let data = selectedSnapshot.representation(using: .png, properties: [:]) {
    do { try data.write(to: output.appendingPathComponent("keyboard-selection.png")) }
    catch { fail("keyboard focus snapshot output") }
} else { fail("keyboard focus png encoding") }
LocalAcceptanceEvidence.record("candidate.body", expected: "候选正文/来源AX正确，非key且在边界内", actual: ["labels": window.displayedCandidateTexts, "input": window.displayedInput, "keyboard_focus": window.permitsKeyboardFocusForTesting])
var selected = -1
window.onSelect = { selected = $0 }
guard window.accessiblePressForTesting(at: 1), selected == 1 else { fail("candidate AX selection") }
LocalAcceptanceEvidence.record("candidate.ax-selection", expected: "直接AX动作映射到候选索引1，不等同VoiceOver", actual: selected)

// Use a real private FFI session for paging; no desktop client or posted events.
let table = root.appendingPathComponent("table.tsv")
try (0..<27).map { "ab\t候选\($0)\t\(100 - $0)\n" }.joined().write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { fail("paging fixture") }
session.setMode("wubi")
_ = session.feed(97); _ = session.feed(98)
func refreshPage() {
    window.update(candidates: session.candidates(limit: 9), pageIndex: session.pageIndex,
                  pageCount: session.pageCount, input: session.buffer)
    window.layout(at: caret, within: area)
}
window.onPage = { delta in session.page(delta); refreshPage() }
refreshPage()
guard session.pageCount == 3, window.pageStateForTesting.text == "1/3",
      !window.pagePressForTesting(-1), window.pagePressForTesting(1),
      session.pageIndex == 1, session.buffer == "ab",
      window.pagePressForTesting(1), session.pageIndex == 2,
      !window.pagePressForTesting(1), window.pageStateForTesting.text == "3/3",
      window.pagePressForTesting(-1), session.pageIndex == 1, session.buffer == "ab"
else { fail("real bounded paging without commit") }
LocalAcceptanceEvidence.record("candidate.paging", expected: "1/3→2/3→3/3→2/3，首尾拒绝越界，保留ab组合", actual: ["label": window.pageStateForTesting.text, "page_index": session.pageIndex, "buffer": session.buffer])
navigation.reset()
guard navigation.move(1, count: 9) == 1,
      let expectedFocused = session.candidates(limit: 9).dropFirst().first?.text,
      session.select(navigation.index) == expectedFocused,
      !session.isComposing
else { fail("space confirmation target follows keyboard focus") }
LocalAcceptanceEvidence.record("candidate.keyboard-confirm-target", expected: "焦点索引1确认后提交当前页显示的第2项", actual: expectedFocused)

func snapshot(_ name: String) {
    guard let image = window.renderSnapshotForTesting(),
          let data = image.representation(using: .png, properties: [:]) else { fail("snapshot " + name) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) }
    catch { fail("snapshot output") }
}
for theme in ["light", "dark"] {
    guard ImeConfig.setString("appearance.theme", theme) else { fail("theme") }
    window.update(candidates: values, pageIndex: 0, pageCount: 3, input: "wq", hint: "键位提示：W 人 · Q 金")
    window.layout(at: caret, within: area)
    snapshot(theme)
}
// Keep the page counter and both 24pt arrows centered across single/multi-digit pages.
for pages in [3, 30, 120] {
    for page in [0, pages - 1] {
        window.update(candidates: values, pageIndex: page, pageCount: pages, input: "tr")
        window.layout(at: caret, within: area)
        let frames = window.pageFramesForTesting
        guard frames.count == 3, abs(frames[0].midY - frames[1].midY) < 0.5,
              abs(frames[1].midY - frames[2].midY) < 0.5,
              frames[0].height == 24, frames[2].height == 24 else { fail("page header common center") }
    }
}
window.update(candidates: values, pageIndex: 0, pageCount: 30, input: "tr")
window.layout(at: caret, within: area)
// 没有 hint/警告时底部留白不得明显大于顶部（否则整块内容看着上移，报告 073）。
let topPadding = window.frame.height - window.pageFramesForTesting[2].maxY
let bottomPadding = window.candidateViewportFrameForTesting.minY
guard bottomPadding <= topPadding + 2 else { fail("balanced candidate padding") }
LocalAcceptanceEvidence.record("candidate.padding", expected: "无 hint 时底部留白不大于顶部+2pt", actual: ["top": topPadding, "bottom": bottomPadding])
snapshot("page-aligned-dark")
LocalAcceptanceEvidence.record("candidate.page-centres", expected: "3/30/120页首尾箭头和页码中心差<0.5pt", actual: window.pageFramesForTesting.map { ["mid_y": $0.midY, "height": $0.height] })
window.update(candidates: values, input: "wq", warning: "虚构繁体资源失败：用于验证错误仍可见，不读取真实文件")
window.layout(at: caret, within: area)
guard window.displayedWarning == "繁体不可用，当前简体" else { fail("fallback visible") }
LocalAcceptanceEvidence.record("candidate.warning", expected: "模拟繁体资源失败时明确当前简体", actual: window.displayedWarning ?? "missing")
snapshot("warning-dark")
let long = String(repeating: "中华人民共和国", count: 10)
window.update(candidates: (0..<9).map { ImeCandidate(text: "\($0)" + long, code: "", source: .phrase, isPrefix: false) },
              pageIndex: 0, pageCount: 2, input: "kwwl")
window.layout(at: caret, within: area)
guard area.contains(window.frame), window.scrollingForTesting,
      window.displayedCandidateTexts.allSatisfy({ $0.contains(long) }) else { fail("bounded long candidates") }
LocalAcceptanceEvidence.record("candidate.long", expected: "九条长词保留全文，可滚动且在给定边界内", actual: ["scrolling": window.scrollingForTesting, "candidate_count": window.displayedCandidateTexts.count, "frame": NSStringFromRect(window.frame)])
snapshot("long-dark")
// Actual shipped a page 2: Unicode remains intact even when native fonts lack glyphs.
let shipped = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("data/generated/pinyin-chars.tsv")
guard let pinyin = ImeSession(wubiPath: table.path, pinyinCharsPath: shipped.path, pinyinWordsPath: nil) else { fail("shipped pinyin fixture") }
pinyin.setMode("pinyin")
pinyin.setPageSize(7)
_ = pinyin.feed(97)
pinyin.page(1)
let rarePage = pinyin.candidates(limit: 7)
guard pinyin.pageIndex == 1, pinyin.pageCount == 2,
      rarePage.map(\.text) == ["錒", "𠼞", "𥥩", "𨉚", "𱚱"] else { fail("shipped a page Unicode identity") }
guard CandidateTextPresentation.display("你好 ABC ❤️") == "你好 ABC ❤️" else { fail("ordinary glyphs unchanged") }
for theme in ["light", "dark"] {
    guard ImeConfig.setString("appearance.theme", theme) else { fail("glyph theme") }
    window.update(candidates: rarePage, pageIndex: 1, pageCount: 2, input: "a")
    window.layout(at: caret, within: NSRect(x: 0, y: 0, width: 1000, height: 400))
    for (index, candidate) in rarePage.enumerated() {
        let display = CandidateTextPresentation.display(candidate.text)
        guard window.displayedCandidateTexts[index] == "\(index + 1) " + display else { fail("glyph label mapping") }
        if display != candidate.text {
            guard display.contains("U+"), window.candidateAccessibilityLabelsForTesting[index].contains("系统字体缺字") else { fail("missing glyph explained") }
        }
    }
    snapshot("pinyin-a-missing-glyph-" + theme)
}
LocalAcceptanceEvidence.record("candidate.glyph-display", expected: "a第二页保留原Unicode；亮暗显示标签和AX与原候选对应", actual: ["original": rarePage.map(\.text), "display": window.displayedCandidateTexts])
window.onSelect = { index in
    let committed = pinyin.select(index)
    guard committed == rarePage[index].text else { fail("glyph replacement must not change committed scalar") }
    LocalAcceptanceEvidence.record("candidate.glyph-commit", expected: "缺字显示不修改选择提交的原字符U+20F1E", actual: committed ?? "missing")
    selected = index
}
guard window.accessiblePressForTesting(at: 1), selected == 1 else { fail("rare glyph real FFI selection") }
let frameBeforeHide = window.frame
window.hide()
guard window.frame == frameBeforeHide else { fail("hidden clear must defer resizing") }
window.hide()
guard window.frame == frameBeforeHide else { fail("repeated hide must defer resizing") }
selected = -1
guard !window.accessiblePressForTesting(at: 0), !window.pagePressForTesting(1),
      selected == -1, window.displayedInput.isEmpty, !window.pageStateForTesting.visible
else { fail("hidden stale actions") }
LocalAcceptanceEvidence.record("candidate.stale", expected: "隐藏后旧选词和翻页动作失效", actual: ["selected": selected, "input": window.displayedInput, "page_visible": window.pageStateForTesting.visible])
// 头部状态芯片：右对齐到翻页区左侧、与翻页按钮同中心线；学习区开启时追加“学”。
window.updateStatus(CandidateStatus(mode: "mixed", english: true, fullWidth: true,
    traditional: false, chinesePunctuation: false))
window.update(candidates: values, pageIndex: 0, pageCount: 30, input: "tr")
window.layout(at: caret, within: NSRect(x: 0, y: 0, width: 1000, height: 400))
let chipTexts = window.stateChipsForTesting
let stripFrame = window.stateStripFrameForTesting
let pagerFrame = window.pageFramesForTesting[0]
guard chipTexts == ["混输", "英文", "全角", "简体", "."] else { fail("state chips " + chipTexts.joined()) }
let inputFrame = window.inputFrameForTesting
// 翻页区为光学对齐整体上提 1.5pt：允许比芯片中心高 0–2pt，而不是要求严格相等。
let pagerLift = pagerFrame.midY - stripFrame.midY
guard stripFrame.maxX <= pagerFrame.minX, stripFrame.minX >= 16,
      pagerLift >= 0.5, pagerLift <= 2.5,
      abs(inputFrame.midY - stripFrame.midY) < 0.5 else { fail("header items not aligned") }
window.updateStatus(CandidateStatus(mode: "pinyin", english: false, fullWidth: false,
    traditional: true, chinesePunctuation: true))
guard window.stateChipsForTesting == ["拼音", "中文", "半角", "繁体", "。"] else { fail("state chips value") }
LocalAcceptanceEvidence.record("candidate.status",
    expected: "两字状态芯片 5 枚（学习区不占芯片）右对齐到翻页左侧且同中心线",
    actual: ["chips": chipTexts, "gap": pagerFrame.minX - stripFrame.maxX,
             "center_delta": abs(stripFrame.midY - pagerFrame.midY)])
// Batched status/content refresh must retain the standalone layout contract.
let batchedWindow = CandidateWindow()
let referenceWindow = CandidateWindow()
for (index, mode) in ["mixed", "wubi", "pinyin", "mixed"].enumerated() {
    let status = CandidateStatus(mode: mode, english: index % 2 == 1,
        fullWidth: index % 2 == 0, traditional: index == 2,
        chinesePunctuation: index != 1)
    let selected = index % values.count
    referenceWindow.updateStatus(status)
    batchedWindow.updateStatus(status, relayout: false)
    for target in [referenceWindow, batchedWindow] {
        target.update(candidates: values, pageIndex: index, pageCount: 30,
            selectedIndex: selected, input: "tr", showsNavigationHint: true)
        target.layout(at: caret, within: NSRect(x: 0, y: 0, width: 1000, height: 400))
    }
    guard batchedWindow.frame == referenceWindow.frame,
          batchedWindow.stateStripFrameForTesting == referenceWindow.stateStripFrameForTesting,
          batchedWindow.inputFrameForTesting == referenceWindow.inputFrameForTesting,
          batchedWindow.stateChipsForTesting == referenceWindow.stateChipsForTesting,
          batchedWindow.displayedCandidateTexts == referenceWindow.displayedCandidateTexts,
          batchedWindow.selectedCandidateIndexForTesting == selected,
          batchedWindow.pageStateForTesting.text == referenceWindow.pageStateForTesting.text
    else { fail("batched status/content layout differs") }
}
LocalAcceptanceEvidence.record("candidate.batched-status",
    expected: "连续状态/候选刷新与默认逐次刷新几何、焦点及分页相同",
    actual: ["chips": batchedWindow.stateChipsForTesting,
             "selected": batchedWindow.selectedCandidateIndexForTesting])
// HUD 主题：同一文案在亮/暗下背景亮度必须不同（报告 080 的暗色不生效回归）。
func backgroundLuminance(_ rep: NSBitmapImageRep?) -> CGFloat? {
    guard let rep, let color = rep.colorAt(x: 4, y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB) else { return nil }
    func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(color.redComponent) + 0.7152 * linear(color.greenComponent) + 0.0722 * linear(color.blueComponent)
}
let lightHUD = StateHUDView.renderForTesting(message: "英文", appearance: NSAppearance(named: .aqua)!)
let darkHUD = StateHUDView.renderForTesting(message: "英文", appearance: NSAppearance(named: .darkAqua)!)
guard let lightL = backgroundLuminance(lightHUD), let darkL = backgroundLuminance(darkHUD),
      lightL - darkL > 0.3 else { fail("state hud ignores appearance") }
LocalAcceptanceEvidence.record("candidate.hud",
    expected: "同一状态 HUD 在亮/暗外观下背景亮度差 > 0.3",
    actual: ["light_luminance": lightL, "dark_luminance": darkL])
// 光标跟随：插入点上方 8pt、水平居中；零矩形视为不可用（不显示）。
let visible = NSRect(x: 0, y: 84, width: 1440, height: 786)
let hudCaret = NSRect(x: 500, y: 300, width: 2, height: 20)
let hudFrame = StateHUDLayout.frame(size: NSSize(width: 100, height: 36),
    caret: hudCaret, visibleFrame: visible)
let edgeCaret = NSRect(x: 10, y: 860, width: 2, height: 20)
let edgeFrame = StateHUDLayout.frame(size: NSSize(width: 100, height: 36),
    caret: edgeCaret, visibleFrame: visible)
guard abs(hudFrame.midX - hudCaret.midX) < 0.5,
      abs(hudFrame.minY - (hudCaret.maxY + StateHUDLayout.gap)) < 0.5,
      hudFrame.width == 100, hudFrame.height == 36,
      edgeFrame.maxY <= visible.maxY - StateHUDLayout.gap,
      StateHUDLayout.isValid(caret: hudCaret),
      !StateHUDLayout.isValid(caret: .zero),
      StateHUDLayout.isValid(caret: NSRect(x: 10, y: 10, width: 0, height: 20)),
      !StateHUDLayout.isValid(caret: nil) else {
    fail("caret hud layout")
}
LocalAcceptanceEvidence.record("candidate.hud-position",
    expected: "HUD 在插入点上方 8pt 居中并夹在屏内；零/空矩形不显示",
    actual: ["frame": NSStringFromRect(hudFrame), "edge": NSStringFromRect(edgeFrame),
             "zero_valid": StateHUDLayout.isValid(caret: .zero)])
// 光标矩形来源：attributes 优先（文本视图位置准），firstRect 兜底（终端）；Finder 无文本不算光标（报告 094 D7/D12）。
let caretLine = NSRect(x: 120, y: 300, width: 2, height: 20)
let textViewEmptyDoc = StateHUDCaretResolver.resolve(
    startIndex: 0, hasText: false, allowsEmptyCaret: true,
    lineRect: { _ in caretLine }, firstRect: { _ in .zero })
let terminalLike = StateHUDCaretResolver.resolve(
    startIndex: 5, hasText: true, allowsEmptyCaret: true,
    lineRect: { _ in .zero }, firstRect: { index in index == 5 ? caretLine : .zero })
let finderLike = StateHUDCaretResolver.resolve(
    startIndex: 0, hasText: false, allowsEmptyCaret: false,
    lineRect: { _ in caretLine }, firstRect: { _ in caretLine })
let textFallback = StateHUDCaretResolver.resolve(
    startIndex: 3, hasText: true, allowsEmptyCaret: true,
    lineRect: { index in index == 1 ? caretLine : .zero }, firstRect: { _ in .zero })
let emptyLineLookback = StateHUDCaretResolver.resolve(
    startIndex: 0, hasText: false, allowsEmptyCaret: true,
    lineRect: { _ in .zero }, firstRect: { _ in .zero })
let attributesPreferred = StateHUDCaretResolver.resolve(
    startIndex: 0, hasText: true, allowsEmptyCaret: true,
    lineRect: { _ in caretLine }, firstRect: { _ in caretLine.offsetBy(dx: 0, dy: 40) })
let onScreen = StateHUDLayout.isOnScreen(caret: caretLine, screens: [visible])
let cgPoint = StateHUDLayout.cgPoint(NSPoint(x: 100, y: 200), primaryTop: 800)
guard cgPoint == CGPoint(x: 100, y: 600) else { fail("hud cocoa to cg point") }
let offScreen = StateHUDLayout.isOnScreen(
    caret: NSRect(x: 100, y: 1609, width: 2, height: 20), screens: [visible])
guard textViewEmptyDoc == caretLine,
      onScreen, !offScreen,
      terminalLike == caretLine,
      finderLike == nil,
      textFallback == caretLine,
      attributesPreferred == caretLine,
      emptyLineLookback == nil else {
    fail("state hud caret resolver")
}
LocalAcceptanceEvidence.record("candidate.hud-source",
    expected: "attributes 优先（位置准）、firstRect 兜底（终端）；Finder 无文本不显示；空文档显示",
    actual: ["empty_doc": textViewEmptyDoc != nil, "terminal_first_rect": terminalLike != nil,
             "finder_pseudo_caret_hidden": finderLike == nil,
             "line_fallback": textFallback != nil,
             "attributes_preferred": attributesPreferred == caretLine,
             "off_screen_rejected": !offScreen,
             "no_rect": emptyLineLookback == nil])

// ADR-215：验收专用数据根覆盖（绝对路径生效、相对路径忽略、未设置走 Application Support）。
let baseSupport = URL(fileURLWithPath: "/Users/example/Library/Application Support")
let defaultSupport = ImePaths.supportDirectory(environment: [:], applicationSupport: baseSupport)
let overrideSupport = ImePaths.supportDirectory(
    environment: ["LAMPYRIS_SUPPORT_DIR": "/tmp/lampyris-acceptance"], applicationSupport: baseSupport)
let relativeIgnored = ImePaths.supportDirectory(
    environment: ["LAMPYRIS_SUPPORT_DIR": "relative/dir"], applicationSupport: baseSupport)
guard defaultSupport?.path == "/Users/example/Library/Application Support/Lampyris",
      overrideSupport?.path == "/tmp/lampyris-acceptance",
      relativeIgnored?.path == "/Users/example/Library/Application Support/Lampyris" else {
    fail("support directory override")
}
LocalAcceptanceEvidence.record("paths.support-dir-override",
    expected: "LAMPYRIS_SUPPORT_DIR 绝对路径生效，相对路径忽略，未设置走 Application Support",
    actual: ["default": defaultSupport?.path ?? "nil", "override": overrideSupport?.path ?? "nil",
             "relative": relativeIgnored?.path ?? "nil"])

print("PASS candidate-presentation: native body/AX, real FFI paging, bounds/long content, light/dark, fallback, non-key panel, stale actions, state chips/HUD")
