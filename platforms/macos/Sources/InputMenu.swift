import AppKit

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
    static let modes = [("mixed", "混输"), ("wubi", "五笔"), ("pinyin", "拼音")]
    static let shortcuts = ["hotkey.toggle_mode", "hotkey.toggle_english", "hotkey.toggle_width",
                            "hotkey.toggle_variant", "hotkey.toggle_punctuation"]

    static func make(state: InputMenuState, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let actions = ["cycleInputMode:", "toggleEnglish:", "toggleWidth:", "toggleVariant:", "togglePunctuation:"]
        for action in actions {
            let item = NSMenuItem(title: "", action: NSSelectorFromString(action), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        let modesMenu = NSMenu(title: "输入模式")
        modesMenu.autoenablesItems = false
        for (index, mode) in modes.enumerated() {
            let actions = ["chooseMixedMode:", "chooseWubiMode:", "choosePinyinMode:"]
            let item = NSMenuItem(title: mode.1, action: NSSelectorFromString(actions[index]), keyEquivalent: "")
            item.target = target
            modesMenu.addItem(item)
        }
        menu.items[0].submenu = modesMenu
        refresh(menu, state: state)
        return menu
    }

    static func nextMode(_ current: String) -> String {
        let index = modes.firstIndex(where: { $0.0 == current }) ?? 0
        return modes[(index + 1) % modes.count].0
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
        modeItem.attributedTitle = nil
        modeItem.title = "输入模式"
        modeItem.setAccessibilityValue(mode)
        if #available(macOS 14.0, *) {
            // AppKit lays out the trailing status immediately before the submenu arrow.
            if modeItem.badge?.stringValue != mode { modeItem.badge = NSMenuItemBadge(string: mode) }
        } else {
            // The older native menu has no trailing status API. Measure the whole menu,
            // including configured shortcuts, rather than pinning a tab to a fixed x.
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .right, location: max(100, menu.size.width - 60))]
            modeItem.attributedTitle = NSAttributedString(string: "输入模式\t" + mode,
                attributes: [.paragraphStyle: paragraph, .font: NSFont.menuFont(ofSize: 0)])
        }
        menu.items[0].toolTip = "点击循环切换；移到右侧子菜单可直接选择。"
        for (item, mode) in zip(menu.items[0].submenu?.items ?? [], modes) {
            item.state = mode.0 == state.mode ? .on : .off
            item.isEnabled = state.enabled
        }
    }
}
