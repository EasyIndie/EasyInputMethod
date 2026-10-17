import AppKit
import InputMethodKit

/// Current values, rebuilt from the session and the shared configuration snapshot.
struct InputMenuState {
    let mode: String
    let language: String
    let width: String
    let variant: String
    let punctuation: String
    let enabled: Bool
}

/// Public AppKit menu contract; callbacks also accept IMK command dictionaries.
enum InputStateMenu {
    enum Command: Int {
        case toggleEnglish = 2, toggleWidth, toggleVariant, togglePunctuation
        case mixed, wubi, pinyin
    }

    static let action = NSSelectorFromString("performInputMenuCommand:")
    static let modes = [("mixed", "混输"), ("wubi", "五笔"), ("pinyin", "拼音")]
    static let shortcuts = ["hotkey.toggle_mode", "hotkey.toggle_english", "hotkey.toggle_width",
                            "hotkey.toggle_variant", "hotkey.toggle_punctuation"]

    static func make(state: InputMenuState, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // A submenu parent has no business command. AppKit assigns submenuAction: itself.
        menu.addItem(NSMenuItem(title: "输入模式", action: nil, keyEquivalent: ""))
        let commands: [Command] = [.toggleEnglish, .toggleWidth, .toggleVariant, .togglePunctuation]
        for command in commands {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.tag = command.rawValue
            item.target = target
            menu.addItem(item)
        }
        let modesMenu = NSMenu(title: "输入模式")
        modesMenu.autoenablesItems = false
        for (index, mode) in modes.enumerated() {
            let item = NSMenuItem(title: mode.1, action: action, keyEquivalent: "")
            item.tag = [Command.mixed, .wubi, .pinyin][index].rawValue
            item.target = target
            modesMenu.addItem(item)
        }
        menu.items[0].submenu = modesMenu
        refresh(menu, state: state)
        return menu
    }

    static func command(from sender: Any?) -> Command? {
        let item: NSMenuItem?
        if let direct = sender as? NSMenuItem {
            item = direct
        } else {
            item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as String] as? NSMenuItem
        }
        guard let item, item.isEnabled, item.action == action else { return nil }
        return Command(rawValue: item.tag)
    }

    static func refresh(_ menu: NSMenu, state: InputMenuState) {
        guard menu.items.count >= 5 else { return }
        let mode = modes.first(where: { $0.0 == state.mode })?.1 ?? "混输"
        let titles = ["输入模式：" + mode, state.language + "输入", state.width + "输入",
                      state.variant + "输入", state.punctuation]
        for (item, title) in zip(menu.items.prefix(5), titles) {
            item.title = title
            item.state = .off
            item.isEnabled = state.enabled
        }
        let modeItem = menu.items[0]
        // Mode commands persist through ime-config even before IMK activates a session.
        modeItem.isEnabled = true
        modeItem.setAccessibilityValue(mode)
        modeItem.toolTip = nil
        modeItem.keyEquivalent = ""
        modeItem.keyEquivalentModifierMask = []
        for (item, mode) in zip(menu.items[0].submenu?.items ?? [], modes) {
            item.state = mode.0 == state.mode ? .on : .off
            item.isEnabled = true
        }
    }
}
