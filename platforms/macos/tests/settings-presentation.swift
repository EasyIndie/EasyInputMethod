import Cocoa
import ime
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else { fail("private config") }
let panel = SettingsPanel.shared
panel.prepare()
let options = SettingsSchema.options()
guard panel.sectionCount == 4, panel.rowCount == options.count, options.count == 15,
      Set(panel.displayedOptionKeys) == Set(options.map(\.key)), !panel.isVisibleForTesting,
      !panel.dictionaryActionsEnabledForTesting, panel.navigationIsNativeForTesting
else { fail("schema/native toolbar/session availability") }
func snapshot(_ image: NSBitmapImageRep?, _ name: String) {
    guard let data = image?.representation(using: .png, properties: [:]) else { fail("snapshot " + name) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { fail("snapshot write") }
}
let scopes = [[0], [1,2], [3], []]
for index in 0..<4 {
    panel.selectSectionForTesting(index)
    guard panel.selectedSectionForTesting == index, panel.navigationIsNativeForTesting,
          Set(panel.visibleOptionKeysForTesting) == Set(options.filter { scopes[index].contains($0.scope) }.map(\.key))
    else { fail("pane mapping " + String(index)) }
    for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        guard let appearance = NSAppearance(named: appearance) else { fail("appearance") }
        snapshot(panel.renderSnapshotForTesting(appearance: appearance, includingChrome: true), "pane-\(index)-\(theme)")
        snapshot(panel.renderMinimumSizeForTesting(appearance: appearance), "minimum-\(index)-\(theme)")
        guard !panel.isVisibleForTesting else { fail("offscreen render became visible") }
    }
}
guard ImeConfig.setString("appearance.theme", "dark") else { fail("theme write") }
panel.configChanged("appearance.theme")
guard panel.configuredAppearanceForTesting == .darkAqua else { fail("theme update") }
panel.reportFailure("mode")
guard panel.statusForTesting.hasPrefix("保存失败：") else { fail("failure visibility") }
let table = root.appendingPathComponent("table.tsv")
try "ab\t测试\t1\n".write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { fail("session") }
panel.bindSessionForTesting(session)
guard panel.dictionaryActionsEnabledForTesting else { fail("session enable") }
panel.bindSessionForTesting(nil)
guard !panel.dictionaryActionsEnabledForTesting else { fail("session disable") }
panel.selectSectionForTesting(2)
panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
panel.prepare()
guard panel.selectedSectionForTesting == 2, panel.rowCount == 15, panel.navigationIsNativeForTesting,
      !panel.isVisibleForTesting else { fail("rebuild with transient pane retention") }
print("PASS settings-presentation: schema/panes, native toolbar, private config, errors, disabled operations, light/dark/minimum, offscreen rebuild")
