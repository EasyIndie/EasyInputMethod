import Cocoa
import ime

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let catalog = SymbolCatalog.shared
guard catalog.loadError == nil else { fail("catalog load: \(catalog.loadError ?? "?")") }
guard catalog.symbols.count >= 250 else { fail("symbols \(catalog.symbols.count)") }
guard catalog.emoji.count > 3_700 else { fail("emoji \(catalog.emoji.count)") }
guard SymbolCatalog.symbolCategories.count == 6 else { fail("symbol categories") }
guard catalog.emojiGroups.count == 9 else { fail("emoji groups \(catalog.emojiGroups.count)") }
guard catalog.prefixCategories.count == 7 else { fail("prefix categories") }

let punctuation = catalog.items(in: SymbolCatalog.symbolCategories[0])
guard punctuation.count >= 40 else { fail("punctuation \(punctuation.count)") }
guard catalog.items(in: SymbolCatalog.symbolCategories[3]).count >= 20 else { fail("arrows") }
guard catalog.emoji.allSatisfy({ !$0.nameZh.isEmpty }) else { fail("emoji without zh name") }

let laugh = catalog.search("笑")
guard laugh.count >= 20, laugh.contains(where: { $0.text == "😀" }) else { fail("search 笑") }
let heart = catalog.search("heart")
guard heart.count >= 20, heart.contains(where: { $0.text == "❤️" }) else { fail("search heart") }
let hands = catalog.search("牵手")
guard hands.count >= 40 else { fail("search 牵手") }
let pinyin = catalog.search("xiao")
guard pinyin.count >= 20, pinyin.contains(where: { $0.text == "😀" || $0.text == "😄" }) else {
    fail("search pinyin xiao")
}
guard catalog.search("逗号").contains(where: { $0.text == "，" }) else { fail("search symbol") }

let picker = SymbolPickerWindow.shared
picker.prepareForTesting()
guard picker.panelForTesting != nil else { fail("panel") }
guard picker.selectCategoryForTesting("punctuation"), picker.itemCountForTesting >= 40 else {
    fail("picker punctuation")
}
guard picker.selectCategoryForTesting("Smileys & Emotion"), picker.itemCountForTesting >= 100 else {
    fail("picker emoji group")
}
picker.setSearchForTesting("笑")
guard picker.itemCountForTesting >= 20 else { fail("picker search") }
var inserted: String?
picker.setInsertHandlerForTesting { inserted = $0 }
guard let first = picker.insertFirstForTesting(), !first.isEmpty else { fail("picker insert") }
guard inserted == first else { fail("insert callback") }

var state = SymbolCompositionState()
guard !state.isActive else { fail("initial state") }
state.phase = .categories
guard state.isActive else { fail("categories state") }
state.page = 2; state.selected = 3
state.reset()
guard !state.isActive, state.page == 0, state.selected == 0 else { fail("reset") }
state.phase = .items(SymbolCatalog.symbolCategories[1])
guard !state.isEmojiCategory else { fail("symbol category flagged emoji") }

// ADR-363：面板保持客户端焦点时，按键由 IMK 转发；必须走进程内组合而不是裸 ASCII。
let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
let fieldHost = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 240, height: 60),
                         styleMask: [.titled], backing: .buffered, defer: false)
fieldHost.contentView?.addSubview(field)
func forwarded(_ chars: String, _ code: UInt16 = 0,
               flags: NSEvent.ModifierFlags = []) -> InHostTextInput.ForwardedResult {
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: 0, windowNumber: 0, context: nil, characters: chars,
        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    return InHostTextInput.shared.handleForwardedKey(event, field: field)
}
func isConsumed(_ result: InHostTextInput.ForwardedResult) -> Bool {
    if case .consumed = result { return true }
    return false
}
func isIgnored(_ result: InHostTextInput.ForwardedResult) -> Bool {
    if case .ignored = result { return true }
    return false
}
guard isConsumed(forwarded("a")) else { fail("字母应进入进程内组合") }
guard isConsumed(forwarded("\u{1b}", 53)) else { fail("Esc 应取消组合") }
guard isIgnored(forwarded(" ", 49)) else { fail("未组合时空格应放行给面板") }
guard isConsumed(forwarded("a")) else { fail("取消后可重新组合") }
guard case .committed(let committed) = forwarded(" ", 49), !committed.isEmpty else {
    fail("空格应提交组合文本")
}
guard isIgnored(forwarded("a", 0, flags: .command)) else { fail("⌘ 快捷键应放行") }

print("PASS symbol-picker: catalog/search/panel/prefix-state/in-host-composition")
