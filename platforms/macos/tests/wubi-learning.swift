import Cocoa
import ime
func require(_ condition: Bool, _ name: String) {
    if !condition { FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8)); exit(1) }
}
let single = WubiLearning.lookup("你")
require(single?.code == "wqiy", "full code rather than short input")
require(single?.characters.first?.roots.map(\.text) == ["亻", "⺈", "小"], "readable actual roots")
require(single?.characters.first?.roots.map(\.key) == ["W", "Q", "I"], "aligned root codes")
require(single?.characters.first?.recognition?.key == "Y", "separate recognition")
let me = WubiLearning.lookup("我")
require(me?.code == "trnt" && me?.characters.first?.roots.map(\.text) == ["丿", "扌", "斜钩", "末撇"], "verified special last-stroke roots")
require(me?.characters.first?.recognition == nil, "four-root code has no invented recognition")
for text in ["我们", "我国", "特别", "特点", "突然", "投入"] {
    require(WubiLearning.lookup(text)?.characters.allSatisfy { !$0.roots.isEmpty } == true, "feedback phrase coverage " + text)
}
let phrase = WubiLearning.lookup("中华人民共和国")
require(phrase?.code == "kwwl" && phrase?.characters.count == 7, "long phrase summary and every character")
require(phrase?.characters[3].code == "nav" && phrase?.characters[3].recognition?.key == "V", "verified long-word decomposition")
require(WubiLearning.lookup("你好")?.code == "wqvb", "phrase code")
require(WubiLearning.lookup("😀")?.code == nil, "missing code")
require(WubiLearning.lookup("是")?.characters[0].roots.isEmpty == true, "missing explanation remains explicit")
require(WubiLearning.lookup("人")?.characters[0].category == "key_name", "key-name category")
for input in ["", "你\t好", String(repeating: "你", count: 86)] {
    require(WubiLearning.lookup(input) == nil, "bounded invalid input")
}
print("PASS wubi-learning: real Rust ABI, ownership, full codes, readable roots, long words, missing data and bounds")

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let privateRoot = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
require(ime_config_init(privateRoot.appendingPathComponent("config.toml").path) == IME_OK, "private config")
require(!ImeConfig.bool("candidate.show_wubi_learning"), "collapsed default from schema")
require(ImeConfig.string("hotkey.toggle_wubi_learning") == "ctrl+shift+l", "learning shortcut default from schema")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "save display preference")
let window = CandidateWindow()
let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
func snapshot(_ name: String) {
    guard let image = window.renderSnapshotForTesting(), let data = image.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { exit(1) }
}
for theme in ["light", "dark"] {
    require(ImeConfig.setString("appearance.theme", theme), "theme")
    for text in ["你", "我", "我们", "特点", "突然", "投入", "中华人民共和国", "😀"] {
        window.update(candidates: [ImeCandidate(text: text, code: "ni", source: .pinyin, isPrefix: false)], input: "ni")
        window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
        require(window.learningVisibleForTesting && !window.permitsKeyboardFocusForTesting && area.contains(window.frame), "mode-independent non-key bounded extension")
        snapshot(text + "-" + theme)
        if text == "中华人民共和国" {
            window.toggleLearningDetailsForTesting()
            window.toggleLearningCharacterForTesting(0)
            window.toggleLearningCharacterForTesting(3)
            require(area.contains(window.frame) && window.frame.height <= 428, "bounded long-word detail")
            snapshot("long-expanded-" + theme)
        }
    }
}
require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "hide preference")
window.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)], input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
require(!window.learningVisibleForTesting, "preference hides extension")
window.hide()
require(!window.learningVisibleForTesting, "hidden panel clears learning")
print("PASS wubi-learning-presentation: private schema, mode-independent extension, long-word disclosure, bounded details, light/dark and stale clearing")

// Exercise the actual default through the session, without rebinding it.
let table = privateRoot.appendingPathComponent("learning-test.tsv")
try "wq\t你\t10\nwqiy\t你\t10\n".write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { exit(1) }
session.setMode("wubi")
_ = session.feed(119); _ = session.feed(113)
let originalBuffer = session.buffer
let originalPage = session.pageIndex
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: "L", charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
require(session.shortcut(event, persistMode: true) == .handled && ImeConfig.bool("candidate.show_wubi_learning"), "shortcut toggles same persisted preference")
require(session.buffer == originalBuffer && session.pageIndex == originalPage, "shortcut preserves composition and page")
let oldWidth = session.isFullWidth
let oldWidthEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
require(session.shortcut(oldWidthEvent, persistMode: true) == .unmatched && session.isFullWidth == oldWidth, "shift-space no longer toggles by default")
let widthEvent = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
require(session.shortcut(widthEvent, persistMode: true) == .handled && session.isFullWidth != oldWidth, "new width shortcut toggles")
require(session.shortcut(widthEvent, persistMode: true) == .handled && session.isFullWidth == oldWidth, "new width shortcut restores")

require(!ImeConfig.setString("hotkey.toggle_wubi_learning", "ctrl+shift+m"), "shortcut collision rejected")
print("PASS learning shortcut: same preference, composition preserved, conflict rejected")

require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "matched collapsed")
let matched = ["你", "你好", "您", "拟"].map { ImeCandidate(text: $0, code: "wq", source: .codeTable, isPrefix: false) }
require(ImeConfig.setString("appearance.theme", "light"), "matched theme")
window.update(candidates: matched, pageIndex: 0, pageCount: 12, input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let stableWidth = window.frame.width
require(stableWidth == 400, "reviewed standard candidate width")
snapshot("matched-collapsed-light")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "show stable learning")
window.update(candidates: matched, pageIndex: 0, pageCount: 12, input: "wq")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
require(window.frame.width == stableWidth, "learning preserves candidate body width")
snapshot("matched-learning-light")
window.hide()

require(WubiLearning.lookup(String(repeating: "人", count: 85))?.characters.count == 85, "legal long word has teaching data")
require(WubiLearning.lookup(String(repeating: "a", count: 256))?.characters.count == 256, "legal byte boundary")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "lifecycle visibility")
window.update(candidates: [ImeCandidate(text: "中华人民共和国", code: "kwwl", source: .phrase, isPrefix: false)], input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
guard let oldAction = window.learningActionForTesting else { exit(1) }
window.hide()
require(oldAction.target == nil && oldAction.action == nil, "old learning actions invalidated")
for theme in ["light", "dark"] {
    require(ImeConfig.setString("appearance.theme", theme), "learning contrast theme")
    window.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)], input: "wq")
    window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
    require(window.learningTextContrastForTesting >= 4.5, "learning text contrast")
}
window.hide()

require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "stable detail preference")
window.update(candidates: [ImeCandidate(text: "中华人民共和国", code: "kwwl", source: .phrase, isPrefix: false)], input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let stableAction = window.learningActionForTesting
var selectionCalls = 0
window.onSelect = { _ in selectionCalls += 1 }
window.toggleLearningDetailsForTesting()
require(window.learningActionForTesting === stableAction, "summary AX identity retained")
window.scrollLearningForTesting(45)
let origin = window.learningScrollOriginForTesting
window.toggleLearningCharacterForTesting(5)
require(abs(window.learningScrollOriginForTesting.y - origin.y) < 1 && selectionCalls == 0, "disclosure preserves scroll without selection")
let longCandidates = (0..<9).map { _ in ImeCandidate(text: String(repeating: "中华人民共和国", count: 8), code: "kwwl", source: .phrase, isPrefix: false) }
let tight = NSRect(x: 0, y: 0, width: 500, height: 500)
require(ImeConfig.setToml("candidate.show_wubi_learning", "false"), "body baseline")
window.update(candidates: longCandidates, input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: tight)
let baselineViewport = window.candidateViewportForTesting
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "body with teaching")
window.update(candidates: longCandidates, input: "kwwl")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: tight)
window.toggleLearningDetailsForTesting()
require(window.candidateViewportForTesting == baselineViewport && tight.contains(window.frame), "teaching cannot steal candidate viewport")
window.hide()

// Reproduce the reported seven-candidate header and teaching layout at the same time.
require(ImeConfig.setString("appearance.theme", "light"), "feedback fixture appearance")
let feedbackCandidates = ["我", "我们", "我国", "特别", "特点", "突然", "投入"].map {
    ImeCandidate(text: $0, code: "tr", source: .codeTable, isPrefix: false)
}
window.update(candidates: feedbackCandidates, pageIndex: 0, pageCount: 30, input: "tr")
window.layout(at: NSRect(x: 20, y: 20, width: 2, height: 20), within: area)
let headerFrames = window.pageFramesForTesting
require(window.learningVisibleForTesting && window.pageStateForTesting.text == "1/30"
    && abs(headerFrames[0].midY - headerFrames[1].midY) < 0.5
    && abs(headerFrames[1].midY - headerFrames[2].midY) < 0.5, "reported page header and teaching together")
snapshot("feedback-tr-light")
window.hide()
