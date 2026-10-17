import AppKit
import InputMethodKit
import ime

func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("FAIL \(message)\n", stderr); exit(1) }
}
func pump(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(1)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return condition()
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let data = URL(fileURLWithPath: CommandLine.arguments[2])
let config = root.appendingPathComponent("config.toml")
require(ime_config_init(config.path) == IME_OK, "private configuration")
guard let session = ImeSession(wubiPath: data.appendingPathComponent("wubi86-core.tsv").path,
    pinyinCharsPath: data.appendingPathComponent("pinyin-chars.tsv").path,
    pinyinWordsPath: data.appendingPathComponent("pinyin-core.tsv").path) else { exit(1) }
require(session.setVariantData(data.appendingPathComponent("variant-s2t.tsv").path) == IME_OK, "real variant data")
session.prepare()
let dictionary = root.appendingPathComponent("user-dictionary.tsv")
let dictionaryBefore = try? Data(contentsOf: dictionary)
let adapter = PreviewInputMenu(session: session)
var cancellations = 0
var changes = 0
var failures: [String] = []
adapter.onCancelComposition = { cancellations += 1; session.focusOut() }
adapter.onChange = { changes += 1 }
adapter.onFailure = { failures.append($0) }
adapter.refresh()
let menu = adapter.menu
require(menu.delegate === adapter && menu.items.count == 8, "real shared flat menu")
require(menu.items[6].keyEquivalent == "s" && menu.items[6].keyEquivalentModifierMask == [.control, .shift], "settings shortcut shown")
require(menu.items[7].keyEquivalent == "a" && menu.items[7].keyEquivalentModifierMask == [.control, .shift], "about shortcut shown")
let parent = menu.items[0]
require(parent.submenu == nil && parent.action == InputStateMenu.action && parent.tag == 1, "mode row is a clickable command")
require(parent.title == "混输模式", "mode row title shows the current mode")
LocalAcceptanceEvidence.record("menu.parent-cycle", expected: "模式行可点击循环，右侧显示当前模式",
    actual: ["mode": session.mode, "action": NSStringFromSelector(parent.action!), "tag": parent.tag, "title": parent.title])
var seen: [[String: String]] = []
for expected in ["wubi", "pinyin", "mixed"] {
    menu.performActionForItem(at: 0)
    require(session.mode == expected && ImeConfig.string("mode") == expected, "each cycle click persists only private config")
    let label = InputStateMenu.modes.first { $0.0 == expected }?.1 ?? ""
    require(parent.accessibilityValue() as? String == label, "menu reflects the cycle")
    require(parent.title == label + "模式", "title follows the cycle")
    seen.append(["mode": expected, "title": parent.title])
}
LocalAcceptanceEvidence.record("menu.cycle-order", expected: "连续点击依次得到五笔/拼音/混输并写回私有配置", actual: ["steps": seen])
_ = session.feed(119); _ = session.feed(113)
let prefix = session.buffer
let beforeCancel = cancellations
adapter.selectMode("mixed")
require(session.buffer == prefix && cancellations == beforeCancel, "same mode preserves composition")
LocalAcceptanceEvidence.record("menu.same-mode", expected: "重复选择同模式保留组合", actual: ["buffer": session.buffer, "cancellations": cancellations - beforeCancel])
adapter.selectMode("wubi")
require(!session.isComposing && cancellations == beforeCancel + 1, "different mode cancels without commit")
LocalAcceptanceEvidence.record("menu.change-mode", expected: "切换不同模式取消组合，不提交", actual: ["composing": session.isComposing, "cancellations": cancellations - beforeCancel])
for (index, title) in [(1, "英文输入"), (2, "全角输入"), (3, "繁体输入"), (4, "英文标点")] {
    menu.performActionForItem(at: index)
    require(menu.items[index].title == title && menu.items[index].state == .off, "session state label " + title)
    menu.performActionForItem(at: index)
}
// Drain queued changes before checking a fresh external preference update.
LocalAcceptanceEvidence.record("menu.states", expected: "四项状态双向切换且无勾选", actual: ["titles": menu.items[1...4].map(\.title), "checks": menu.items[1...4].map { $0.state.rawValue }])
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
let oldChanges = changes
require(ImeConfig.setString("mode", "pinyin"), "external settings mode")
require(pump { changes > oldChanges && session.mode == "pinyin" && menu.items[0].accessibilityValue() as? String == "拼音" }, "settings notification updates session and menu")
LocalAcceptanceEvidence.record("menu.external-settings", expected: "配置通知刷新同一会话和菜单", actual: ["session": session.mode, "label": menu.items[0].accessibilityValue() as? String ?? ""])
require(ImeConfig.setString("hotkey.toggle_width", "ctrl+alt+w"), "external shortcut change")
require(pump { menu.items[2].keyEquivalent == "w" && menu.items[2].keyEquivalentModifierMask == [.control, .option] }, "shortcut labels refresh through real config subscription")
LocalAcceptanceEvidence.record("menu.shortcut-refresh", expected: "外部快捷键改为control+option+w后刷新", actual: ["key": menu.items[2].keyEquivalent, "modifiers": menu.items[2].keyEquivalentModifierMask.rawValue])
let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .shift], timestamp: 0,
    windowNumber: 0, context: nil, characters: "M", charactersIgnoringModifiers: "m", isARepeat: false, keyCode: 46)!
require(session.shortcut(event, persistMode: true) == .handled, "preview keyboard persists owned mode")
require(pump { session.mode == "mixed" && menu.items[0].accessibilityValue() as? String == "混输" }, "keyboard mode updates same menu")
LocalAcceptanceEvidence.record("menu.shortcut-event", expected: "合成NSEvent切模式后菜单同步；不等同物理键盘", actual: ["mode": session.mode, "label": menu.items[0].accessibilityValue() as? String ?? ""])
RunLoop.current.run(until: Date().addingTimeInterval(0.05))
let beforeBytes = try Data(contentsOf: config)
let lock = URL(fileURLWithPath: config.path + ".lock")
try Data("owned test lock".utf8).write(to: lock)
adapter.selectMode("wubi")
require(session.mode == "mixed" && menu.items[0].accessibilityValue() as? String == "混输" && !failures.isEmpty, "write failure keeps actual mode and reports error")
require(try Data(contentsOf: config) == beforeBytes, "failed write leaves private bytes unchanged")
LocalAcceptanceEvidence.record("menu.write-failure", expected: "私有锁导致写失败，模式和配置字节保持", actual: ["mode": session.mode, "error_count": failures.count, "config_unchanged": try Data(contentsOf: config) == beforeBytes])
try FileManager.default.removeItem(at: lock)
adapter.selectMode("wubi")
require(session.mode == "wubi", "recover after lock removal")
LocalAcceptanceEvidence.record("menu.recovery", expected: "解除私有锁后可恢复修改", actual: session.mode)
var settings = 0
var about = 0
adapter.onSettings = { settings += 1 }
adapter.onAbout = { about += 1 }
menu.performActionForItem(at: 6)
menu.performActionForItem(at: 7)
require(settings == 1 && about == 1, "settings and about route through preview callbacks")
require(menu.items[6].title == "设置" && menu.items[7].title == "关于", "user action labels")
LocalAcceptanceEvidence.record("menu.routes", expected: "设置/关于各触发一次回调，文案无省略号", actual: ["titles": [menu.items[6].title, menu.items[7].title], "settings_calls": settings, "about_calls": about])
require((try? Data(contentsOf: dictionary)) == dictionaryBefore, "no learned or committed text")
LocalAcceptanceEvidence.record("menu.dictionary", expected: "模式/状态操作不增加私有词库学习", actual: ["unchanged": (try? Data(contentsOf: dictionary)) == dictionaryBefore])
print("PASS preview-menu: real session/shared flat menu/private configuration, click cycle, state toggles, external preferences, keyboard, failure recovery and no learning")
