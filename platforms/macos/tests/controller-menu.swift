import AppKit
import InputMethodKit
import ime

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let root = CommandLine.arguments[1]
func require(_ condition: Bool, _ message: String) {
    if !condition { fputs("FAIL \(message)\n", stderr); exit(1) }
}
// Exercise the real trace writer, with no desktop events or input contents.
let tracePath = root + "/trace.jsonl"
let perf = PerfTrace.shared
require(!perf.enabled && perf.begin() == nil, "trace disabled by default")
var calls = 0
let disabledResult = perf.measure(nil, phase: .preedit) { calls += 1; return 42 }
require(disabledResult == 42 && calls == 1, "disabled trace preserves the operation")
require(!FileManager.default.fileExists(atPath: tracePath), "disabled trace never writes")
PerfTrace.configureForTest(tracePath: tracePath)
guard let firstTrace = perf.begin(), let secondTrace = perf.begin() else {
    fatalError("test trace enabled")
}
let measured = perf.measure(firstTrace, phase: .preedit) { calls += 1; return 7 }
perf.measure(firstTrace, phase: .preedit) { calls += 1 }
perf.measure(secondTrace, phase: .commit) { calls += 1 }
perf.measure(secondTrace, phase: .hide) { }
require(measured == 7 && calls == 4, "tracing preserves calls and returned values")
perf.finish(firstTrace, engine: perf.stamp(), candidates: 7, committed: false)
perf.finish(secondTrace, engine: nil, candidates: 1, committed: true)
let traceRows = try String(contentsOfFile: tracePath, encoding: .utf8).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
require(traceRows.count == 2, "one record per key")
let firstPhases = traceRows[0]["phases"] as! [String: Double]
let secondPhases = traceRows[1]["phases"] as! [String: Double]
require(Set(firstPhases.keys) == ["preeditUs"] && Set(secondPhases.keys) == ["commitUs", "hideUs"],
        "phases remain isolated between keys")
require(firstPhases["preeditUs"]! >= 0 && secondPhases["commitUs"]! >= 0 && secondPhases["hideUs"]! >= 0,
        "nonnegative phase durations")
require(traceRows[0]["phaseSchema"] as? Int == 3, "versioned optional phase fields")
// ADR-258：schema3 只增加 content 子阶段键，其他记录形态不变。
let contentKeys: Set<String> = ["contentStateUs", "contentMeasureUs", "contentSetUs", "contentLayoutUs"]
let contentTrace = perf.begin()!
for phase in [PerfTrace.Phase.contentState, .contentMeasure, .contentSet, .contentLayout] {
    perf.measure(contentTrace, phase: phase) { }
}
perf.finish(contentTrace, engine: nil, candidates: 3, committed: false)
let contentRows = try String(contentsOfFile: tracePath, encoding: .utf8).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
}
let contentPhases = contentRows.last!["phases"] as! [String: Double]
require(Set(contentPhases.keys) == contentKeys, "schema3 content phases are named exactly")
require(traceRows[0]["candidates"] as? Int == 7 && traceRows[1]["committed"] as? Bool == true,
        "legacy candidate and commit fields remain compatible")
require(traceRows[1]["engineUs"] as? Double == -1, "missing engine stamp remains compatible")
require(Set(traceRows[0].keys) == ["engineUs", "totalUs", "candidates", "committed", "phaseSchema", "phases"],
        "trace contains only approved timing fields")
let tracePermissions = try FileManager.default.attributesOfItem(atPath: tracePath)[.posixPermissions] as! Int
require(tracePermissions == 0o600, "new trace file is private")
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
require(coldMenu.items.count == 9, "five rows plus separator, update, settings and about")
require(coldMenu.items.prefix(5).allSatisfy { $0.submenu == nil }, "no nested menus")
require(coldMenu.items[1...4].allSatisfy { !$0.isEnabled }, "session-only toggles stay disabled before activation")
require(coldMenu.items[6].title == "检查更新…" && coldMenu.items[6].keyEquivalent == "g"
    && coldMenu.items[6].keyEquivalentModifierMask == [.option], "update entry shows configured shortcut")
require(coldMenu.items[7].keyEquivalent == "," && coldMenu.items[7].keyEquivalentModifierMask == [.option], "settings shortcut in menu")
require(coldMenu.items[8].keyEquivalent == "a" && coldMenu.items[8].keyEquivalentModifierMask == [.option], "about shortcut in menu")
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
require(LampyrisInputController.caretLookupIndex(selectionLocation: 0, length: 0) == 0, "empty caret")
require(LampyrisInputController.caretLookupIndex(selectionLocation: 1, length: 1) == 0, "end-of-text caret")
require(LampyrisInputController.caretLookupIndex(selectionLocation: 3, length: 5) == 3, "mid-text caret")
require(LampyrisInputController.caretLookupIndex(selectionLocation: NSNotFound, length: 5) == 0, "unknown selection")
print("PASS controller-menu: flat menu, cold/warm cycle through the IMK service boundary, states and reactivation")

require(StateFeedback.language(true) == "英文" && StateFeedback.language(false) == "中文", "language feedback")
require(StateFeedback.width(true) == "全角" && StateFeedback.width(false) == "半角", "width feedback")
require(StateFeedback.punctuation(true) == "中文标点" && StateFeedback.punctuation(false) == "英文标点", "punctuation feedback")
require(StateFeedback.variant(true) == "繁体" && StateFeedback.variant(false) == "简体", "variant feedback")
require(StateFeedback.mode("mixed") == "混输模式" && StateFeedback.mode("wubi") == "五笔模式"
    && StateFeedback.mode("pinyin") == "拼音模式", "mode feedback")
require(StateFeedback.learning(true) == "学习区：开" && StateFeedback.learning(false) == "学习区：关", "learning feedback")
