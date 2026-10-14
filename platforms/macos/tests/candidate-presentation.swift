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
var selected = -1
window.onSelect = { selected = $0 }
guard window.accessiblePressForTesting(at: 1), selected == 1 else { fail("candidate AX selection") }

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
window.update(candidates: values, input: "wq", warning: "虚构繁体资源失败：用于验证错误仍可见，不读取真实文件")
window.layout(at: caret, within: area)
guard window.displayedWarning == "繁体不可用，当前简体" else { fail("fallback visible") }
snapshot("warning-dark")
let long = String(repeating: "中华人民共和国", count: 10)
window.update(candidates: (0..<9).map { ImeCandidate(text: "\($0)" + long, code: "", source: .phrase, isPrefix: false) },
              pageIndex: 0, pageCount: 2, input: "kwwl")
window.layout(at: caret, within: area)
guard area.contains(window.frame), window.scrollingForTesting,
      window.displayedCandidateTexts.allSatisfy({ $0.contains(long) }) else { fail("bounded long candidates") }
snapshot("long-dark")
window.hide()
selected = -1
guard !window.accessiblePressForTesting(at: 0), !window.pagePressForTesting(1),
      selected == -1, window.displayedInput.isEmpty, !window.pageStateForTesting.visible
else { fail("hidden stale actions") }
print("PASS candidate-presentation: native body/AX, real FFI paging, bounds/long content, light/dark, fallback, non-key panel, stale actions")
