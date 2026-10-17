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
        case cycleMode = 1, toggleEnglish, toggleWidth, toggleVariant, togglePunctuation
    }

    static let action = NSSelectorFromString("performInputMenuCommand:")
    static let modes = [("mixed", "混输"), ("wubi", "五笔"), ("pinyin", "拼音")]
    static let shortcuts = ["hotkey.toggle_mode", "hotkey.toggle_english", "hotkey.toggle_width",
                            "hotkey.toggle_variant", "hotkey.toggle_punctuation"]

    static func make(state: InputMenuState, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let commands: [Command] = [.cycleMode, .toggleEnglish, .toggleWidth, .toggleVariant, .togglePunctuation]
        for command in commands {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.tag = command.rawValue
            item.target = target
            menu.addItem(item)
        }
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
        // Mode cycling persists through ime-config even before IMK activates a session.
        modeItem.isEnabled = true
        modeItem.setAccessibilityValue(mode)
        modeItem.toolTip = nil
        let row = (modeItem.view as? InputModeMenuView) ?? InputModeMenuView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        row.mode = mode
        row.isEnabled = true
        modeItem.view = row
    }
}

/// One flexible row: title on the left, current mode right-aligned like the other items' shortcuts.
/// Clicking the row cycles the mode; there is no submenu (IMK does not deliver nested commands).
final class InputModeMenuView: NSView {
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

    /// Same right inset AppKit uses for key equivalents and badges.
    var statusInset: CGFloat { 14 }

    /// Right-aligned status text rectangle; ends at the key-equivalent inset.
    var statusRect: NSRect {
        let font = NSFont.menuFont(ofSize: 0)
        let size = (mode as NSString).size(withAttributes: [.font: font])
        let maxX = bounds.maxX - statusInset
        return NSRect(x: maxX - size.width, y: 0, width: size.width, height: bounds.height)
    }

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
        text(mode, in: statusRect, color: secondary, right: true)
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
