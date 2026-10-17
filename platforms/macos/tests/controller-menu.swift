import AppKit
import InputMethodKit
import ime

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = CommandLine.arguments[1]
func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("FAIL \(message)\n", stderr); exit(1) }
}
require(ime_config_init(root + "/config.toml") == IME_OK, "private config")
guard let server = IMKServer(name: "cn.jokerhub.lampyris.probe." + UUID().uuidString,
                            bundleIdentifier: Bundle.main.bundleIdentifier),
      let controller = LampyrisInputController(server: server, delegate: nil, client: nil) else {
    fputs("FAIL private IMK server/controller\n", stderr); exit(1)
}
// IMK may request its menu before this controller has a text session.
let coldMenu = controller.menu()!
require(coldMenu.items.dropFirst().prefix(4).allSatisfy { !$0.isEnabled }, "session-only toggles stay disabled before activation")
require(coldMenu.items[0].isEnabled, "mode parent enabled before activation")
require(coldMenu.items[0].submenu!.items.allSatisfy { $0.isEnabled }, "mode choices enabled before activation")
let coldChoice = coldMenu.items[0].submenu!.items[1]
require(LampyrisProbeDispatchMenuCommand(server, controller, coldChoice, 501), "private IMK service boundary available")
require(ImeConfig.string("mode") == "wubi", "service boundary delivers cold submenu choice")
controller.doCommand(by: coldChoice.action!, command: [kIMKCommandMenuItemName as String: coldChoice])
require(ImeConfig.string("mode") == "wubi", "cold mode command persisted")
require(controller.menu()!.items[0].submenu!.items[1].state == .on, "cold menu reflects persistent choice")
let coldParent = controller.menu()!.items[0]
require(coldParent.view == nil && coldParent.action == NSSelectorFromString("submenuAction:") && coldParent.keyEquivalent.isEmpty, "cold standard parent only expands")
require(InputStateMenu.command(from: coldParent) == nil, "parent is not a mode command")
controller.activateServer(nil)
require(controller.menu()!.items[0].submenu!.items[1].state == .on, "first activation applies cold choice")
for (index, raw) in [(1, "wubi"), (2, "pinyin"), (0, "mixed")] {
    let menu = controller.menu()!
    let item = menu.items[0].submenu!.items[index]
    require(item.isEnabled && controller.responds(to: item.action!), "enabled real selector")
    require(LampyrisProbeDispatchMenuCommand(server, controller, item, 500 + index), "service boundary available")
    require(ImeConfig.string("mode") == raw, "service boundary delivers every submenu choice")
    controller.doCommand(by: item.action!, command: [kIMKCommandMenuItemName as String: item])
    require(ImeConfig.string("mode") == raw, "IMK child command persisted")
    require(controller.menu()!.items[0].submenu!.items[index].state == .on, "real session matches choice")
}
for (index, switched, restored) in [(1, "英文输入", "中文输入"), (2, "全角输入", "半角输入"),
                                    (3, "繁体输入", "简体输入"), (4, "英文标点", "中文标点")] {
    let item = controller.menu()!.items[index]
    require(LampyrisProbeDispatchMenuCommand(server, controller, item, index), "state service boundary available")
    require(controller.menu()!.items[index].title == switched, "service toggles correct state")
    let reverse = controller.menu()!.items[index]
    require(LampyrisProbeDispatchMenuCommand(server, controller, reverse, index), "reverse state service boundary available")
    require(controller.menu()!.items[index].title == restored, "service restores correct state")
    require(ImeConfig.string("mode") == "mixed", "state command does not change input mode")
}
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "pinyin"), "other client changed persistent mode")
controller.activateServer(nil)
require(controller.menu()!.items[0].submenu!.items[2].state == .on, "reactivation applies persisted pinyin")
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "mixed"), "other client changed mixed")
controller.activateServer(nil)
require(controller.menu()!.items[0].submenu!.items[0].state == .on, "reactivation applies persisted mixed")
controller.deactivateServer(nil)
print("PASS controller-menu: IMK service submenu/state dispatch, cold controller and inactive session resynchronization; system menu UI untested")
