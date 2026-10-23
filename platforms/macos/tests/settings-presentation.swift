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
guard panel.sectionCount == 5, panel.rowCount == options.count, options.count == 22,
      Set(panel.displayedOptionKeys) == Set(options.map(\.key)), !panel.isVisibleForTesting,
      !panel.dictionaryActionsEnabledForTesting, panel.navigationIsNativeForTesting
else { fail("schema/native toolbar/session availability") }
panel.selectSectionForTesting(0)
guard panel.visibleOptionKeysForTesting == ["mode", "input.chinese_variant", "input.punctuation", "input.full_width", "wubi.auto_commit", "wubi.z_key", "pinyin.fuzzy"] else { fail("design input grouping and order") }
panel.selectSectionForTesting(1)
guard panel.visibleOptionKeysForTesting == ["candidate.count", "candidate.page_with_comma", "appearance.theme", "candidate.show_wubi_learning"] else { fail("candidate design group order") }
LocalAcceptanceEvidence.record("settings.groups", expected: "输入/候选按Schema分组，所有22项都有入口", actual: ["count": panel.rowCount, "candidate_keys": panel.visibleOptionKeysForTesting])
guard let countOption = options.first(where: { $0.key == "candidate.count" }) else { fail("count schema") }
let numberRow = SettingRow(option: countOption)
numberRow.reload()
for value in ["3", "9", "7"] {
    numberRow.commitNumberForTesting(value)
    guard ImeConfig.int("candidate.count") == Int(value), numberRow.numberValueForTesting == value else { fail("editable native count") }
}
for value in ["", "0", "10", "3.5", "abc"] {
    numberRow.commitNumberForTesting(value)
    guard ImeConfig.int("candidate.count") == 7, numberRow.numberValueForTesting == "7" else { fail("invalid count rollback") }
}
numberRow.commitNumberForTesting("7")
panel.reportSaved()
LocalAcceptanceEvidence.record("settings.count", expected: "接受3/9/7，拒绝空/0/10/小数/字母并保持7", actual: ["configured": ImeConfig.int("candidate.count") ?? -1, "control": numberRow.numberValueForTesting ?? "missing"])
panel.selectSectionForTesting(2)
guard panel.visibleOptionKeysForTesting.last == "hotkey.toggle_wubi_learning" else { fail("design learning shortcut placement") }
for (key, title) in [("hotkey.toggle_width", "⌥F"), ("hotkey.toggle_wubi_learning", "⌥L"), ("hotkey.toggle_english", "⇧"),
                     ("hotkey.open_settings", "⌥,"), ("hotkey.open_about", "⌥A")] {
    panel.rowForTesting(key)?.reload() // The visible show path reloads rows after prepare.
    guard let row = panel.rowForTesting(key), row.shortcutTitleForTesting == title else { fail("shortcut title " + key + " actual=" + (panel.rowForTesting(key)?.shortcutTitleForTesting ?? "missing") + " configured=" + (ImeConfig.string(key) ?? "missing")) }
}
guard let learningRow = panel.rowForTesting("hotkey.toggle_wubi_learning") else { fail("learning row") }
LocalAcceptanceEvidence.record("settings.shortcuts", expected: "宽度/学习/中英/设置/关于按钮显示新默认且无省略号", actual: ["hotkey.toggle_width", "hotkey.toggle_wubi_learning", "hotkey.toggle_english", "hotkey.open_settings", "hotkey.open_about"].map { panel.rowForTesting($0)?.shortcutTitleForTesting ?? "missing" })
for (value, title) in [("", "未设置"), ("alt+l", "⌥L")] {
    guard learningRow.commitTextForTesting(value) else { fail("shortcut write") }
    let deadline = Date().addingTimeInterval(1)
    while learningRow.shortcutTitleForTesting != title && Date() < deadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
    guard learningRow.shortcutTitleForTesting == title else { fail("shortcut notification/rebind title") }
}
LocalAcceptanceEvidence.record("settings.shortcut-rebind", expected: "学习快捷键禁用后重新绑定，按钮随通知刷新", actual: ["stored": ImeConfig.string("hotkey.toggle_wubi_learning") ?? "", "title": learningRow.shortcutTitleForTesting ?? "missing"])
func snapshot(_ image: NSBitmapImageRep?, _ name: String) {

    guard let data = image?.representation(using: .png, properties: [:]) else { fail("snapshot " + name) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { fail("snapshot write") }
}
var helpBaselineGaps: [String: CGFloat] = [:]
func recordHelpBaselines(theme: String) {
    for key in ["mode", "input.full_width", "pinyin.fuzzy", "candidate.show_wubi_learning"] {
        guard panel.visibleOptionKeysForTesting.contains(key), let row = panel.rowForTesting(key),
              let top = row.arrangedSubviews.first as? NSStackView,
              let title = top.arrangedSubviews.first,
              let help = row.arrangedSubviews.last as? NSTextField else { continue }
        func baseline(_ view: NSView) -> CGFloat {
            let y = view.isFlipped ? view.bounds.minY + view.firstBaselineOffsetFromTop
                : view.bounds.maxY - view.firstBaselineOffsetFromTop
            return row.convert(NSPoint(x: 0, y: y), from: view).y
        }
        helpBaselineGaps[theme + ":" + key] = abs(baseline(title) - baseline(help))
    }
}
let scopes = [[0], [1,2], [3], [], [4]]
for index in 0..<5 {
    panel.selectSectionForTesting(index)
    guard panel.selectedSectionForTesting == index, panel.navigationIsNativeForTesting,
          Set(panel.visibleOptionKeysForTesting) == Set(options.filter { scopes[index].contains($0.scope) }.map(\.key))
    else { fail("pane mapping " + String(index)) }
    for (theme, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        guard let appearance = NSAppearance(named: appearance) else { fail("appearance") }
        snapshot(panel.renderSnapshotForTesting(appearance: appearance, includingChrome: true), "pane-\(index)-\(theme)")
        recordHelpBaselines(theme: theme)
        snapshot(panel.renderMinimumSizeForTesting(appearance: appearance), "minimum-\(index)-\(theme)")
        guard !panel.isVisibleForTesting else { fail("offscreen render became visible") }
    }
}
for theme in ["light", "dark"] {
    let gaps = ["mode", "input.full_width", "pinyin.fuzzy", "candidate.show_wubi_learning"].compactMap {
        helpBaselineGaps[theme + ":" + $0]
    }
    guard gaps.count == 4, let minimum = gaps.min(), let maximum = gaps.max(), minimum >= 20,
          maximum - minimum <= 1.5 else { fail("description baseline spacing: \(helpBaselineGaps)") }
}
let gapData = try JSONSerialization.data(withJSONObject: helpBaselineGaps, options: [.sortedKeys])
try gapData.write(to: output.appendingPathComponent("description-baselines.json"))
LocalAcceptanceEvidence.record("settings.descriptions", expected: "亮暗四项文字基线间距>=20pt且差<=1.5pt", actual: helpBaselineGaps)
LocalAcceptanceEvidence.record("settings.appearances", expected: "五分区亮暗/最小窗/长错误可离屏渲染且窗口不显示", actual: ["panes": panel.sectionCount, "visible": panel.isVisibleForTesting, "native_toolbar": panel.navigationIsNativeForTesting])
guard ImeConfig.setString("appearance.theme", "dark") else { fail("theme write") }
panel.configChanged("appearance.theme")
guard panel.configuredAppearanceForTesting == .darkAqua else { fail("theme update") }
LocalAcceptanceEvidence.record("settings.theme", expected: "主题配置通知生效", actual: panel.configuredAppearanceForTesting?.rawValue ?? "missing")
panel.reportFailure("mode")
guard panel.statusForTesting.hasPrefix("保存失败：") else { fail("failure visibility") }
LocalAcceptanceEvidence.record("settings.failure", expected: "保存错误可见，非虚假成功", actual: panel.statusForTesting)
let table = root.appendingPathComponent("table.tsv")
try "ab\t测试\t1\n".write(to: table, atomically: true, encoding: .utf8)
guard let session = ImeSession(wubiPath: table.path, pinyinCharsPath: nil, pinyinWordsPath: nil) else { fail("session") }
panel.bindSessionForTesting(session)
guard panel.dictionaryActionsEnabledForTesting else { fail("session enable") }
panel.bindSessionForTesting(nil)
guard !panel.dictionaryActionsEnabledForTesting else { fail("session disable") }
LocalAcceptanceEvidence.record("settings.dictionary-session", expected: "绑定私有会话时可操作词库，解绑后禁用", actual: ["enabled_after_unbind": panel.dictionaryActionsEnabledForTesting])
panel.selectSectionForTesting(2)
panel.windowWillClose(Notification(name: NSWindow.willCloseNotification))
panel.prepare()
guard panel.selectedSectionForTesting == 2, panel.rowCount == 22, panel.navigationIsNativeForTesting,
      !panel.isVisibleForTesting else { fail("rebuild with transient pane retention") }
LocalAcceptanceEvidence.record("settings.reopen", expected: "关闭重建保留分区，19项不丢失，窗口不显示", actual: ["section": panel.selectedSectionForTesting, "rows": panel.rowCount, "visible": panel.isVisibleForTesting])
print("PASS settings-presentation: schema/panes, native toolbar, private config, errors, disabled operations, light/dark/minimum, offscreen rebuild")
