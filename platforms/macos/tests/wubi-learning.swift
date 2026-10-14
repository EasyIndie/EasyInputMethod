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
let phrase = WubiLearning.lookup("中华人民共和国")
require(phrase?.code == "kwwl" && phrase?.characters.count == 7, "long phrase summary and every character")
require(phrase?.characters[3].code == "nav" && phrase?.characters[3].roots.isEmpty == true, "unknown decomposition preserves full code")
require(WubiLearning.lookup("你好")?.code == "wqvb", "phrase code")
require(WubiLearning.lookup("😀")?.code == nil, "missing code")
require(WubiLearning.lookup("人")?.characters[0].category == "key_name", "key-name category")
for input in ["", "你\t好", String(repeating: "你", count: 33)] {
    require(WubiLearning.lookup(input) == nil, "bounded invalid input")
}
print("PASS wubi-learning: real Rust ABI, ownership, full codes, readable roots, long words, missing data and bounds")

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let privateRoot = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
require(ime_config_init(privateRoot.appendingPathComponent("config.toml").path) == IME_OK, "private config")
require(!ImeConfig.bool("candidate.show_wubi_learning"), "collapsed default from schema")
require(ImeConfig.string("hotkey.toggle_wubi_learning") == "none", "unbound shortcut default")
require(ImeConfig.setToml("candidate.show_wubi_learning", "true"), "save display preference")
let window = CandidateWindow()
let area = NSRect(x: 0, y: 0, width: 1000, height: 800)
func snapshot(_ name: String) {
    guard let image = window.renderSnapshotForTesting(), let data = image.representation(using: .png, properties: [:]) else { exit(1) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { exit(1) }
}
for theme in ["light", "dark"] {
    require(ImeConfig.setString("appearance.theme", theme), "theme")
    for text in ["你", "你好", "中华人民共和国", "😀"] {
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

require(ImeConfig.setString("hotkey.toggle_wubi_learning", "ctrl+shift+k"), "bind learning shortcut")
let table = privateRoot.appendingPathComponent("learning-test.tsv")
try "wq\t你\t10\nwqiy\t你\t10\n".write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { exit(1) }
session.setMode("wubi")
_ = session.feed(119); _ = session.feed(113)
let originalBuffer = session.buffer
let originalPage = session.pageIndex
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift],
    timestamp: 0, windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "k", isARepeat: false, keyCode: 40)!
require(session.shortcut(event, persistMode: true) == .handled && ImeConfig.bool("candidate.show_wubi_learning"), "shortcut toggles same persisted preference")
require(session.buffer == originalBuffer && session.pageIndex == originalPage, "shortcut preserves composition and page")
require(!ImeConfig.setString("hotkey.toggle_wubi_learning", "ctrl+shift+m"), "shortcut collision rejected")
print("PASS learning shortcut: same preference, composition preserved, conflict rejected")
