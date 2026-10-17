import AppKit
import InputMethodKit

func require(_ value: Bool, _ message: String) {
    guard value else { fputs("FAIL \(message)\n", stderr); exit(1) }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

final class MenuOwner: NSObject {
    var mode = "mixed"
    var english = false
    var fullWidth = false
    var traditional = false
    var chinesePunctuation = true
    var permitsChange = true
    lazy var menu = InputStateMenu.make(state: snapshot, target: self)
    var snapshot: InputMenuState {
        InputMenuState(mode: mode, language: english ? "英文" : "中文",
            width: fullWidth ? "全角" : "半角", variant: traditional ? "繁体" : "简体",
            punctuation: chinesePunctuation ? "中文标点" : "英文标点", enabled: true)
    }
    func change(_ next: String) {
        if permitsChange { mode = next }
        InputStateMenu.refresh(menu, state: snapshot)
    }
    @objc func performInputMenuCommand(_ sender: Any?) {
        guard let command = InputStateMenu.command(from: sender) else { return }
        switch command {
        case .cycleMode: change(InputStateMenu.nextMode(mode))
        case .toggleEnglish: english.toggle()
        case .toggleWidth: fullWidth.toggle()
        case .toggleVariant: traditional.toggle()
        case .togglePunctuation: chinesePunctuation.toggle()
        }
        InputStateMenu.refresh(menu, state: snapshot)
    }
}
let owner = MenuOwner()
let menu = owner.menu
let parent = menu.items[0]

require(menu.items.count == 5, "one mode row and four state rows")
require(menu.items.allSatisfy { $0.submenu == nil }, "no nested menus: IMK does not deliver their commands")
require(menu.items.allSatisfy { $0.action == InputStateMenu.action && !$0.isHidden }, "shared action without hidden relays")
require(Set(menu.items.map(\.tag)).count == menu.items.count, "commands have distinct stable identities")
require(menu.items.dropFirst().map(\.title) == ["中文输入", "半角输入", "简体输入", "中文标点"], "initial current-state titles")
require(menu.items.allSatisfy { $0.state == .off }, "state rows must not use checkmarks")
require(parent.tag == InputStateMenu.Command.cycleMode.rawValue, "mode row carries the cycle command")
require(parent.target === owner && parent.keyEquivalent.isEmpty && parent.toolTip == nil, "mode row is a plain clickable item")
require((parent.view as? InputModeMenuView)?.mode == "混输", "custom row shows the current mode")
require(parent.accessibilityValue() as? String == "混输", "accessible current mode")
LocalAcceptanceEvidence.record("menu-view.state", expected: "四状态显示当前值且无勾选，模式行右侧显示当前模式",
    actual: ["titles": menu.items.map(\.title), "checks": menu.items.map { $0.state.rawValue },
             "mode": parent.accessibilityValue() as? String ?? ""])
LocalAcceptanceEvidence.record("menu-view.structure", expected: "五行均无子菜单；模式行 action/tag/view 齐备",
    actual: ["submenus": menu.items.filter { $0.submenu != nil }.count,
             "action": NSStringFromSelector(parent.action!), "tag": parent.tag, "view": parent.view != nil])

for sender: Any in [NSMenuItem(title: "x", action: InputStateMenu.action, keyEquivalent: ""),
                    [:] as [String: Any], "wubi"] {
    owner.performInputMenuCommand(sender)
    require(owner.mode == "mixed", "malformed command must not mutate state")
}
let disabledToggle = menu.items[1]
disabledToggle.isEnabled = false
owner.performInputMenuCommand([kIMKCommandMenuItemName as String: disabledToggle])
require(menu.items[1].title == "中文输入", "disabled command must not change state")
disabledToggle.isEnabled = true
for obsolete in [6, 7, 8, 99] {
    let item = NSMenuItem(title: "旧入口", action: InputStateMenu.action, keyEquivalent: "")
    item.tag = obsolete
    require(InputStateMenu.command(from: item) == nil, "removed mode tags stay rejected")
}

var cycled: [[String: String]] = []
for (expected, expectedMode) in [("五笔", "wubi"), ("拼音", "pinyin"), ("混输", "mixed")] {
    menu.performActionForItem(at: 0)
    require(owner.mode == expectedMode, "cycle persisted")
    require(parent.accessibilityValue() as? String == expected, "cycle refreshes the same menu")
    require((parent.view as? InputModeMenuView)?.mode == expected, "trailing status follows the cycle")
    require(parent.title == "输入模式：" + expected, "native proxy fallback retains mode")
    require(parent.submenu == nil, "menu row never gains a submenu")
    cycled.append(["mode": owner.mode, "title": parent.title])
}
require(owner.mode == "mixed", "cycle wraps back to mixed")
LocalAcceptanceEvidence.record("menu-view.cycle", expected: "点击模式行依次循环五笔/拼音/混输并回到同一菜单",
    actual: ["steps": cycled])

let row = parent.view as! InputModeMenuView
var layoutFrames: [[String: Any]] = []
for width: CGFloat in [180, 240, 360] {
    row.setFrameSize(NSSize(width: width, height: 24))
    let statusRight = width - row.statusInset
    require(abs(row.statusRect.maxX - statusRight) < 0.5, "status ends at the key-equivalent inset")
    require(row.statusRect.minX > 90, "status avoids the title")
    layoutFrames.append(["width": width, "status_max_x": row.statusRect.maxX])
}
LocalAcceptanceEvidence.record("menu-view.layout", expected: "180/240/360pt 下状态右端对齐同一右侧内边距，不与标题重叠",
    actual: layoutFrames)
row.mode = "五笔"
let copy = parent.copy() as! NSMenuItem
require((copy.view as? InputModeMenuView)?.mode == "五笔", "native menu copy retains status")
LocalAcceptanceEvidence.record("menu-view.copy", expected: "菜单复制保留当前模式", actual: (copy.view as? InputModeMenuView)?.mode ?? "missing")

InputStateMenu.refresh(menu, state: owner.snapshot)
owner.permitsChange = false
menu.performActionForItem(at: 0)
require(owner.mode == "mixed" && parent.accessibilityValue() as? String == "混输", "failed change keeps the displayed state")
owner.permitsChange = true
for (index, switched, restored) in [(1, "英文输入", "中文输入"), (2, "全角输入", "半角输入"),
                                    (3, "繁体输入", "简体输入"), (4, "英文标点", "中文标点")] {
    menu.performActionForItem(at: index)
    require(menu.items[index].title == switched && menu.items[index].state == .off, "toggle updates current title without check")
    menu.performActionForItem(at: index)
    require(menu.items[index].title == restored && menu.items[index].state == .off, "toggle restores current title")
}
print("PASS input-menu: five flat rows, mode row cycles, no submenu, status aligned, rejected old tags, failed change and toggles")

if let output = ProcessInfo.processInfo.environment["LAMPYRIS_ACCEPTANCE_OUTPUT"] {
    var snapshots: [String] = []
    for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let view = InputModeMenuView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        guard let appearance = NSAppearance(named: name) else { exit(1) }
        view.appearance = appearance
        for state in ["normal", "highlight", "disabled"] {
            view.isEnabled = state != "disabled"
            if state == "highlight", let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
                modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                view.mouseEntered(with: event)
            }
            var data: Data?
            appearance.performAsCurrentDrawingAppearance {
                let image = NSImage(size: view.bounds.size, flipped: true) { rect in
                    NSColor.windowBackgroundColor.setFill(); rect.fill()
                    view.draw(rect)
                    return true
                }
                if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    data = rep.representation(using: .png, properties: [:])
                }
            }
            guard let data else { exit(1) }
            let filename = "mode-\(theme)-\(state).png"
            try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(filename))
            snapshots.append(filename)
        }
    }
    LocalAcceptanceEvidence.record("menu-view.render", expected: "模式行在亮/暗、常态/高亮/禁用可绘制，无箭头", actual: snapshots)
}
