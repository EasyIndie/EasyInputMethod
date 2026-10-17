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
        case .mixed: change("mixed")
        case .wubi: change("wubi")
        case .pinyin: change("pinyin")
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
let commands = Array(menu.items.dropFirst()) + menu.items[0].submenu!.items
require(menu.items.count == 5 && menu.items[0].submenu!.items.count == 3, "visible hierarchy unchanged")
require(commands.allSatisfy { $0.action == InputStateMenu.action && !$0.isHidden }, "shared action without hidden relays")
require(Set(commands.map(\.tag)).count == commands.count, "commands have distinct stable identities")
let unknown = NSMenuItem(title: "五笔", action: InputStateMenu.action, keyEquivalent: "")
unknown.tag = 999
for sender: Any in [unknown, [:] as [String: Any], "wubi"] {
    owner.performInputMenuCommand(sender)
    require(owner.mode == "mixed" && !owner.english, "malformed command must not mutate state")
}
let disabled = menu.items[0].submenu!.items[1]
disabled.isEnabled = false
owner.performInputMenuCommand([kIMKCommandMenuItemName as String: disabled])
require(owner.mode == "mixed", "disabled command must not change mode")
disabled.isEnabled = true
require(menu.items.dropFirst().map(\.title) == ["中文输入", "半角输入", "简体输入", "中文标点"], "initial current-state titles")
require(menu.items[0].accessibilityValue() as? String == "混输", "accessible current mode")
require(menu.items.allSatisfy { $0.state == .off }, "state rows must not use checkmarks")
let parent = menu.items[0]
require(parent.action == NSSelectorFromString("submenuAction:") && parent.target === parent.submenu, "standard AppKit submenu parent")
require(parent.view == nil && parent.keyEquivalent.isEmpty && parent.toolTip == nil, "no custom drawing, parent shortcut or hover hint")
LocalAcceptanceEvidence.record("menu-view.state", expected: "四状态显示当前值且无勾选，一级标题含模式", actual: ["titles": menu.items.map(\.title), "checks": menu.items.map { $0.state.rawValue }])
LocalAcceptanceEvidence.record("menu-view.structure", expected: "一个标准父项、三个二级选项，系统绘制箭头，无自定义view", actual: ["parent_action": NSStringFromSelector(parent.action!), "custom_view": parent.view != nil, "choices": parent.submenu!.items.map(\.title)])
require(InputStateMenu.command(from: parent) == nil, "parent is never a business command")
owner.performInputMenuCommand([kIMKCommandMenuItemName as String: parent])
require(owner.mode == "mixed", "opening parent cannot change mode")
let obsoleteCycle = NSMenuItem(title: "输入模式", action: InputStateMenu.action, keyEquivalent: "")
obsoleteCycle.tag = 1
require(InputStateMenu.command(from: obsoleteCycle) == nil, "old parent command rejected")
LocalAcceptanceEvidence.record("menu-view.parent-inert", expected: "父项及旧循环tag不执行模式命令", actual: ["mode": owner.mode, "old_tag_rejected": InputStateMenu.command(from: obsoleteCycle) == nil])
let copy = parent.copy() as! NSMenuItem
require(copy.view == nil && copy.title == parent.title && copy.submenu?.items.map(\.title) == ["混输", "五笔", "拼音"], "copy keeps native hierarchy and mode title")
LocalAcceptanceEvidence.record("menu-view.copy", expected: "复制保留标准层级和当前标题，不携带自绘视图", actual: ["title": copy.title, "choices": copy.submenu!.items.map(\.title), "custom_view": copy.view != nil])
let submenu = menu.items[0].submenu!
for (index, raw) in [(1,"wubi"),(2,"pinyin"),(0,"mixed")] {
    let item = submenu.items[index]
    // IMK's doCommand forwards its dictionary rather than the NSMenuItem sender.
    _ = owner.perform(item.action!, with: [kIMKCommandMenuItemName as String: item] as NSDictionary)
    require(owner.mode == raw && submenu.items[index].state == .on, "dictionary callback explicit mode choice")
    require(parent.title == "输入模式：" + submenu.items[index].title, "native parent title updates")
    require(submenu.items.filter { $0.state == .on }.count == 1, "one selected mode")
}
owner.permitsChange = false
submenu.performActionForItem(at: 1)
require(owner.mode == "mixed" && menu.items[0].accessibilityValue() as? String == "混输", "failed change must retain displayed state")
for (index, switched, restored) in [(1,"英文输入","中文输入"),(2,"全角输入","半角输入"),(3,"繁体输入","简体输入"),(4,"英文标点","中文标点")] {
    menu.performActionForItem(at: index)
    require(menu.items[index].title == switched && menu.items[index].state == .off, "toggle updates current title without check")
    menu.performActionForItem(at: index)
    require(menu.items[index].title == restored && menu.items[index].state == .off, "toggle restores current title")
}
print("PASS input-menu: native submenu parent, explicit IMK dictionary callbacks, unique mode check, failed change and bidirectional toggles")
