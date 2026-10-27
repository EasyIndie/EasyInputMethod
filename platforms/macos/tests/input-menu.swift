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
require(parent.target === owner && parent.keyEquivalent.isEmpty && parent.toolTip == nil && parent.view == nil,
        "mode row is a plain title item")
require(parent.title == "混输模式", "title reflects the current mode")
require(parent.accessibilityValue() as? String == "混输", "accessible current mode")
LocalAcceptanceEvidence.record("menu-view.state", expected: "四状态显示当前值且无勾选，模式行标题显示当前模式",
    actual: ["titles": menu.items.map(\.title), "checks": menu.items.map { $0.state.rawValue },
             "mode": parent.accessibilityValue() as? String ?? ""])
LocalAcceptanceEvidence.record("menu-view.structure", expected: "五行均无子菜单/自定义视图；模式行 action/tag 齐备",
    actual: ["submenus": menu.items.filter { $0.submenu != nil }.count, "views": menu.items.filter { $0.view != nil }.count,
             "action": NSStringFromSelector(parent.action!), "tag": parent.tag])

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
for (title, expectedMode) in [("五笔模式", "wubi"), ("拼音模式", "pinyin"), ("混输模式", "mixed")] {
    menu.performActionForItem(at: 0)
    require(owner.mode == expectedMode, "cycle persisted")
    require(parent.title == title, "clicking the row updates the same menu title")
    require(parent.submenu == nil && parent.view == nil, "the row never gains a submenu or view")
    cycled.append(["title": parent.title, "mode": owner.mode])
}
require(owner.mode == "mixed", "cycle wraps back to mixed")
LocalAcceptanceEvidence.record("menu-view.cycle", expected: "点击模式行依次循环五笔/拼音/混输并通过标题显示",
    actual: ["steps": cycled])

let copy = parent.copy() as! NSMenuItem
require(copy.title == parent.title && copy.tag == parent.tag && copy.submenu == nil, "native menu copy keeps the mode title")
LocalAcceptanceEvidence.record("menu-view.copy", expected: "菜单复制保留当前标题与命令", actual: ["title": copy.title, "tag": copy.tag])

InputStateMenu.refresh(menu, state: owner.snapshot)
owner.permitsChange = false
menu.performActionForItem(at: 0)
require(owner.mode == "mixed" && parent.title == "混输模式", "failed change keeps the displayed state")
owner.permitsChange = true
for (index, switched, restored) in [(1, "英文输入", "中文输入"), (2, "全角输入", "半角输入"),
                                    (3, "繁体输入", "简体输入"), (4, "英文标点", "中文标点")] {
    menu.performActionForItem(at: index)
    require(menu.items[index].title == switched && menu.items[index].state == .off, "toggle updates current title without check")
    menu.performActionForItem(at: index)
    require(menu.items[index].title == restored && menu.items[index].state == .off, "toggle restores current title")
}
print("PASS input-menu: five flat rows, mode title cycles, no submenu/view, rejected old tags, failed change and toggles")

// ADR-294：更新程序只按 bundle id 定位，目录名（正式 `LampyrisUpdateCheck.app` 或历史上手工改名的
// `Lampyris Update.app`）不是判据。
func makeUpdaterBundle(in directory: URL, named name: String, identifier: String) -> URL {
    let bundle = directory.appendingPathComponent(name)
    let contents = bundle.appendingPathComponent("Contents")
    try! FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": identifier,
                               "CFBundleExecutable": "LampyrisUpdateCheck",
                               "CFBundlePackageType": "APPL"]
    let data = try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    try! data.write(to: contents.appendingPathComponent("Info.plist"))
    return bundle
}
let workspace = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("lampyris-updater-lookup-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workspace) }
require(UpdateEntry.updater(in: workspace) == nil, "empty directory has no updater")
_ = makeUpdaterBundle(in: workspace, named: "Something Else.app",
                      identifier: "cn.jokerhub.Lampyris.WebsiteUpdateCheck")
require(UpdateEntry.updater(in: workspace)?.lastPathComponent == "Something Else.app",
        "bundle id decides, not the directory name")
let official = makeUpdaterBundle(in: workspace, named: UpdateEntry.updaterBundleName,
                                 identifier: UpdateEntry.updaterBundleID)
_ = makeUpdaterBundle(in: workspace, named: "Lampyris Update.app",
                      identifier: UpdateEntry.updaterBundleID)
_ = makeUpdaterBundle(in: workspace, named: "Unrelated.app",
                      identifier: "cn.jokerhub.inputmethod.Lampyris")
require(UpdateEntry.updater(in: workspace)?.standardizedFileURL.path == official.standardizedFileURL.path,
        "official bundle name wins over legacy names")
try! FileManager.default.removeItem(at: official)
require(UpdateEntry.updater(in: workspace)?.lastPathComponent == "Lampyris Update.app",
        "legacy directory name stays launchable")
require(UpdateEntry.installDirectories.count == 2, "only ~/Applications and /Applications are searched")
LocalAcceptanceEvidence.record("update-entry.lookup",
    expected: "更新程序按 bundle id 查找，包名不再要求手工改名",
    actual: ["bundle": UpdateEntry.updaterBundleName, "directories": UpdateEntry.installDirectories.map(\.path)])
print("PASS update-entry: bundle-id lookup ignores directory name and prefers the official bundle name")
