import AppKit

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
    @objc func cycleInputMode(_ sender: Any?) { change(InputStateMenu.nextMode(mode)) }
    @objc func chooseMixedMode(_ sender: Any?) { change("mixed") }
    @objc func chooseWubiMode(_ sender: Any?) { change("wubi") }
    @objc func choosePinyinMode(_ sender: Any?) { change("pinyin") }
    @objc func toggleEnglish(_ sender: Any?) { english.toggle(); InputStateMenu.refresh(menu, state: snapshot) }
    @objc func toggleWidth(_ sender: Any?) { fullWidth.toggle(); InputStateMenu.refresh(menu, state: snapshot) }
    @objc func toggleVariant(_ sender: Any?) { traditional.toggle(); InputStateMenu.refresh(menu, state: snapshot) }
    @objc func togglePunctuation(_ sender: Any?) { chinesePunctuation.toggle(); InputStateMenu.refresh(menu, state: snapshot) }
}
let owner = MenuOwner()
let menu = owner.menu
require(menu.items.dropFirst().map(\.title) == ["中文输入", "半角输入", "简体输入", "中文标点"], "initial current-state titles")
require(menu.items[0].accessibilityValue() as? String == "混输", "accessible current mode")
require(menu.items.allSatisfy { $0.state == .off }, "state rows must not use checkmarks")
require(menu.items[0].action != nil && menu.items[0].submenu?.items.count == 3, "parent action and native submenu coexist")
LocalAcceptanceEvidence.record("menu-view.state", expected: "四状态显示当前值且无勾选，模式父子入口同时存在", actual: ["titles": menu.items.dropFirst().map(\.title), "checks": menu.items.map { $0.state.rawValue }, "mode": menu.items[0].accessibilityValue() as? String ?? ""])
for expected in ["五笔", "拼音", "混输"] {
    menu.performActionForItem(at: 0)
    require(menu.items[0].accessibilityValue() as? String == expected, "parent cycle refreshes same menu")
    require((menu.items[0].view as? InputModeMenuView)?.mode == expected, "plain trailing status")
    require(menu.items[0].title == "输入模式：" + expected, "native proxy fallback retains mode")
    require(menu.items[0].toolTip == nil, "no mode hover hint")
    if #available(macOS 14.0, *) {
        require(menu.items[0].badge == nil, "no tag styling")
    }
    require(menu.items[0].submenu!.items.filter { $0.state == .on }.map(\.title) == [expected], "unique submenu check")
}
let wideItem = NSMenuItem(title: String(repeating: "较长的菜单条目", count: 6), action: nil, keyEquivalent: "")
menu.addItem(wideItem)
InputStateMenu.refresh(menu, state: owner.snapshot)
require(menu.items[0].accessibilityValue() as? String == "混输", "wide menu retains current mode")
if #available(macOS 14.0, *) {
    require(menu.items[0].badge == nil, "wide menu has no badge")
}
let row = menu.items[0].view as! InputModeMenuView
var layoutFrames: [[String: Any]] = []
for width: CGFloat in [160, 240, 360] {
    row.setFrameSize(NSSize(width: width, height: 24))
    require(row.arrowFrame.minX - row.statusFrame.maxX == 11, "status stays next to arrow across menu widths")
    require(row.statusFrame.maxY <= row.bounds.maxY && row.statusFrame.minX > 90, "status avoids title and row bounds")
    layoutFrames.append(["width": width, "status": NSStringFromRect(row.statusFrame), "arrow": NSStringFromRect(row.arrowFrame)])
}
LocalAcceptanceEvidence.record("menu-view.layout", expected: "160/240/360pt宽度下状态靠右并紧邻箭头，不与标题重叠", actual: layoutFrames)
row.mode = "五笔"
let copy = menu.items[0].copy() as! NSMenuItem
require((copy.view as? InputModeMenuView)?.mode == "五笔", "native menu copy retains status")
LocalAcceptanceEvidence.record("menu-view.copy", expected: "菜单复制保留当前模式", actual: (copy.view as? InputModeMenuView)?.mode ?? "missing")
InputStateMenu.refresh(menu, state: owner.snapshot)
menu.removeItem(wideItem)
let submenu = menu.items[0].submenu!
for (index, raw) in [(1,"wubi"),(2,"pinyin"),(0,"mixed")] {
    let item = submenu.items[index]
    // IMK's doCommand forwards its dictionary rather than the NSMenuItem sender.
    _ = owner.perform(item.action!, with: ["IMKCommandMenuItemName": item] as NSDictionary)
    require(owner.mode == raw && submenu.items[index].state == .on, "dictionary callback explicit mode choice")
}
owner.permitsChange = false
menu.performActionForItem(at: 0)
require(owner.mode == "mixed" && menu.items[0].accessibilityValue() as? String == "混输", "failed change must retain displayed state")
for (index, switched, restored) in [(1,"英文输入","中文输入"),(2,"全角输入","半角输入"),(3,"繁体输入","简体输入"),(4,"英文标点","中文标点")] {
    menu.performActionForItem(at: index)
    require(menu.items[index].title == switched && menu.items[index].state == .off, "toggle updates current title without check")
    menu.performActionForItem(at: index)
    require(menu.items[index].title == restored && menu.items[index].state == .off, "toggle restores current title")
}
print("PASS input-menu: current-state titles, parent cycle, explicit IMK dictionary callbacks, unique mode check, failed change and bidirectional toggles")

if let output = ProcessInfo.processInfo.environment["LAMPYRIS_ACCEPTANCE_OUTPUT"] {
    guard NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: nil) != nil else { exit(1) }
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
    LocalAcceptanceEvidence.record("menu-view.render", expected: "系统SF箭头与原生菜单字体亮暗/模拟高亮/禁用可绘制；非系统菜单跟踪", actual: snapshots)
}
