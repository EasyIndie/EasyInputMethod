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
window.hide()
selected = -1
guard !window.accessiblePressForTesting(at: 0), !window.pagePressForTesting(1),
      selected == -1, window.displayedInput.isEmpty, !window.pageStateForTesting.visible
else { fail("hidden stale actions") }
LocalAcceptanceEvidence.record("candidate.stale", expected: "隐藏后旧选词和翻页动作失效", actual: ["selected": selected, "input": window.displayedInput, "page_visible": window.pageStateForTesting.visible])
print("PASS candidate-presentation: native body/AX, real FFI paging, bounds/long content, light/dark, fallback, non-key panel, stale actions")
