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
controller.activateServer(nil)
for (index, raw) in [(1, "wubi"), (2, "pinyin"), (0, "mixed")] {
    let menu = controller.menu()!
    let item = menu.items[0].submenu!.items[index]
    require(item.isEnabled && controller.responds(to: item.action!), "enabled real selector")
    controller.doCommand(by: item.action!, command: [kIMKCommandMenuItemName as String: item])
    require(ImeConfig.string("mode") == raw, "IMK child command persisted")
    require(controller.menu()!.items[0].submenu!.items[index].state == .on, "real session matches choice")
}
let parent = controller.menu()!.items[0]
controller.doCommand(by: parent.action!, command: [kIMKCommandMenuItemName as String: parent])
require(ImeConfig.string("mode") == "wubi", "IMK parent command cycles")
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "pinyin"), "other client changed persistent mode")
controller.activateServer(nil)
require(controller.menu()!.items[0].submenu!.items[2].state == .on, "reactivation applies persisted pinyin")
controller.deactivateServer(nil)
require(ImeConfig.setString("mode", "mixed"), "other client changed mixed")
controller.activateServer(nil)
require(controller.menu()!.items[0].submenu!.items[0].state == .on, "reactivation applies persisted mixed")
controller.deactivateServer(nil)
print("PASS controller-menu: real IMK command dispatch and inactive session resynchronization; system proxy untested")
