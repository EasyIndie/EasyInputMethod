import AppKit
import InputMethodKit
import ime

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = CommandLine.arguments[1]
func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("FAIL \(message)\n", stderr); exit(1) }
}
func label(_ mode: String) -> String {
    InputStateMenu.modes.first { $0.0 == mode }?.1 ?? ""
}
require(ime_config_init(root + "/config.toml") == IME_OK, "private config")
guard let server = IMKServer(name: "cn.jokerhub.lampyris.probe." + UUID().uuidString,
                            bundleIdentifier: Bundle.main.bundleIdentifier),
      let controller = LampyrisInputController(server: server, delegate: nil, client: nil) else {
    fputs("FAIL private IMK server/controller\n", stderr); exit(1)
}
// IMK may request its menu before this controller has a text session.
let coldMenu = controller.menu()!
require(coldMenu.items.count == 8, "five rows plus separator, settings and about")
require(coldMenu.items.prefix(5).allSatisfy { $0.submenu == nil }, "no nested menus")
require(coldMenu.items[1...4].allSatisfy { !$0.isEnabled }, "session-only toggles stay disabled before activation")
require(coldMenu.items[6].keyEquivalent == "," && coldMenu.items[6].keyEquivalentModifierMask == [.option], "settings shortcut in menu")
require(coldMenu.items[7].keyEquivalent == "a" && coldMenu.items[7].keyEquivalentModifierMask == [.option], "about shortcut in menu")
require(coldMenu.items[0].isEnabled, "mode row enabled before activation")
require(coldMenu.items[0].tag == 1, "mode row carries the cycle command")
require(LampyrisProbeDispatchMenuCommand(server, controller, coldMenu.items[0], 501), "cold row dispatches through the service boundary")
require(ImeConfig.string("mode") == "wubi", "cold row cycle persisted")
require(controller.menu()!.items[0].accessibilityValue() as? String == "五笔", "cold menu reflects persistent choice")
var row = controller.menu()!.items[0]
controller.doCommand(by: row.action!, command: [kIMKCommandMenuItemName as String: row])
require(ImeConfig.string("mode") == "pinyin", "IMK row command cycles")
require(controller.menu()!.items[0].accessibilityValue() as? String == "拼音", "menu follows the row command")
controller.activateServer(nil)
require(controller.menu()!.items[0].accessibilityValue() as? String == "拼音", "first activation applies cold choice")
for expected in ["mixed", "wubi"] {
    row = controller.menu()!.items[0]
    require(row.isEnabled && controller.responds(to: row.action!), "enabled real selector")
    require(LampyrisProbeDispatchMenuCommand(server, controller, row, 500), "service boundary available")
    require(ImeConfig.string("mode") == expected, "service boundary cycles to " + expected)
    require(controller.menu()!.items[0].accessibilityValue() as? String == label(expected), "real session matches cycle")
}
let modeBeforeToggles = ImeConfig.string("mode")
for (index, switched, restored) in [(1, "英文输入", "中文输入"), (2, "全角输入", "半角输入"),
                                    (3, "繁体输入", "简体输入"), (4, "英文标点", "中文标点")] {
    let item = controller.menu()!.items[index]
    require(LampyrisProbeDispatchMenuCommand(server, controller, item, index), "state service boundary available")
    require(controller.menu()!.items[index].title == switched, "service toggles correct state")
    let reverse = controller.menu()!.items[index]
    require(LampyrisProbeDispatchMenuCommand(server, controller, reverse, index), "reverse state service boundary available")
    require(controller.menu()!.items[index].title == restored, "service restores correct state")
}
require(ImeConfig.string("mode") == modeBeforeToggles, "state commands do not change the input mode")
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "pinyin"), "other client changed persistent mode")
controller.activateServer(nil)
require(controller.menu()!.items[0].accessibilityValue() as? String == "拼音", "reactivation applies persisted pinyin")
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "mixed"), "other client changed mixed")
controller.activateServer(nil)
require(controller.menu()!.items[0].accessibilityValue() as? String == "混输", "reactivation applies persisted mixed")
print("PASS controller-menu: flat menu, cold/warm cycle through the IMK service boundary, states and reactivation")
