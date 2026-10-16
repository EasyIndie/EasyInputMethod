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
        if #available(macOS 14.0, *) { modeItem.badge = nil }
        let row = (modeItem.view as? InputModeMenuView) ?? InputModeMenuView(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        row.mode = mode
        row.isEnabled = state.enabled
        modeItem.view = row
        // Preserve a useful native fallback if an IMK menu proxy drops the view.
        modeItem.title = "输入模式：" + mode
        modeItem.toolTip = nil
        for (item, mode) in zip(menu.items[0].submenu?.items ?? [], modes) {
            item.state = mode.0 == state.mode ? .on : .off
            item.isEnabled = state.enabled
        }
    }
}

/// One flexible row; the containing NSMenu retains native submenu tracking.
final class InputModeMenuView: NSView {
    private let submenuArrow = NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: nil)
    private var pointerInside = false
    private var hoverArea: NSTrackingArea?
    var mode = "混输" { didSet { setAccessibilityValue(mode); needsDisplay = true } }
    var isEnabled = true { didSet { setAccessibilityEnabled(isEnabled); needsDisplay = true } }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("输入模式")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        mode = coder.decodeObject(forKey: "mode") as? String ?? "混输"
        isEnabled = coder.decodeBool(forKey: "modeEnabled")
        setAccessibilityValue(mode)
        setAccessibilityEnabled(isEnabled)
        autoresizingMask = [.width]
        setAccessibilityElement(true)
        setAccessibilityRole(.menuItem)
        setAccessibilityLabel("输入模式")
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(mode, forKey: "mode")
        coder.encode(isEnabled, forKey: "modeEnabled")
    }

    var statusFrame: NSRect { NSRect(x: bounds.maxX - 68, y: 0, width: 40, height: bounds.height) }
    var arrowFrame: NSRect { NSRect(x: bounds.maxX - 17, y: bounds.midY - 6, width: 8, height: 12) }

    override func draw(_ dirtyRect: NSRect) {
        let selected = isEnabled && (pointerInside || enclosingMenuItem?.isHighlighted == true)
        if selected {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        let foreground: NSColor = !isEnabled ? .disabledControlTextColor : selected ? .selectedMenuItemTextColor : .labelColor
        let secondary: NSColor = !isEnabled ? .disabledControlTextColor : selected ? .selectedMenuItemTextColor : .secondaryLabelColor
        let font = NSFont.menuFont(ofSize: 0)
        func text(_ string: String, in rect: NSRect, color: NSColor, right: Bool = false) {
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (string as NSString).size(withAttributes: attributes)
            (string as NSString).draw(at: NSPoint(x: right ? rect.maxX - size.width : rect.minX,
                y: rect.midY - size.height / 2), withAttributes: attributes)
        }
        text("输入模式", in: NSRect(x: 14, y: 0, width: 85, height: bounds.height), color: foreground)
        text(mode, in: statusFrame, color: secondary, right: true)
        if let symbol = submenuArrow?
            .withSymbolConfiguration(.init(pointSize: font.pointSize, weight: .semibold))?
            .withSymbolConfiguration(.init(paletteColors: [foreground])) {
            let scale = min(arrowFrame.width / symbol.size.width, arrowFrame.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            let frame = NSRect(x: arrowFrame.midX - size.width / 2, y: arrowFrame.midY - size.height / 2,
                width: size.width, height: size.height)
            symbol.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1,
                respectFlipped: true, hints: nil)
        }
    }

    override func updateTrackingAreas() {
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) { pointerInside = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false; needsDisplay = true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pointerInside = false
        needsDisplay = true
    }

    @discardableResult
    private func cycle() -> Bool {
        guard isEnabled, let item = enclosingMenuItem, let action = item.action else { return false }
        return NSApp.sendAction(action, to: item.target, from: item)
    }

    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        cycle()
    }

    override func accessibilityPerformPress() -> Bool { cycle() }
}
