import Cocoa
import ime
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); exit(1)
}
NSApplication.shared.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else { fail("private config") }
let candidate = CandidateWindow()
let values = [ImeCandidate(text: "你好", code: "wq", source: .codeTable, isPrefix: false),
              ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false)]
let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua),
    ("contrast-light", .accessibilityHighContrastAqua), ("contrast-dark", .accessibilityHighContrastDarkAqua)]
var contrasts: [[String: Any]] = []
var requests: [[String: Any]] = []
func save(_ image: NSBitmapImageRep?, _ name: String) {
    guard let data = image?.representation(using: .png, properties: [:]) else { fail("snapshot " + name) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { fail("snapshot") }
}
for (theme, name) in appearances {
    guard let appearance = NSAppearance(named: name) else { fail("appearance") }
    let highContrastPolicy = theme.hasPrefix("contrast-")
    requests.append(["requested": name.rawValue, "resolved": appearance.name.rawValue,
      "highContrastPolicy": highContrastPolicy, "systemHighContrast": NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast])
    appearance.performAsCurrentDrawingAppearance {
        let secondary = ImeAppearance.secondaryTextColor(for: appearance, highContrast: highContrastPolicy)
        let pairs: [(String, NSColor, NSColor, CGFloat)] = [
            ("body", .labelColor, .windowBackgroundColor, 4.5),
            ("secondary", secondary, .windowBackgroundColor, 4.5),
            ("error", ImeAppearance.errorText, .windowBackgroundColor, 4.5),
            ("readonly", .labelColor, .textBackgroundColor, 4.5),
            ("hover", .labelColor, ImeAppearance.hoverBackground(), 4.5),
            ("hover-secondary", secondary, ImeAppearance.hoverBackground(), 4.5),
        ]
        for (role, foreground, background, threshold) in pairs {
            let ratio = ImeAppearance.contrast(foreground, over: background)
            guard ratio >= threshold else { fail("contrast \(theme)/\(role)=\(ratio)") }
            contrasts.append(["appearance": theme, "role": role, "ratio": Double(ratio), "threshold": Double(threshold)])
        }
        if highContrastPolicy {
            let ratio = ImeAppearance.contrast(ImeAppearance.candidateBorderColor(highContrast: true), over: .windowBackgroundColor)
            guard ratio >= 3 else { fail("high contrast boundary") }
            contrasts.append(["appearance": theme, "role": "boundary", "ratio": Double(ratio), "threshold": 3])
        }
    }
    if highContrastPolicy { continue } // Do not label aliased base appearances as actual system high contrast.
    candidate.update(candidates: values, pageIndex: 1, pageCount: 4, input: "wq", hint: "键位提示：W 人 · Q 金", warning: "合成资源失败，用于错误状态验证")
    candidate.setAppearanceForTesting(appearance)
    candidate.layout(at: NSRect(x: 310, y: 290, width: 2, height: 20), within: NSRect(x: 0, y: 0, width: 320, height: 300))
    candidate.simulateHover(at: 1, true)
    save(candidate.renderSnapshotForTesting(), "candidate-\(theme)")
    SettingsPanel.shared.selectSectionForTesting(1)
    save(SettingsPanel.shared.renderLongErrorForTesting(appearance: appearance), "settings-\(theme)")
    InfoWindow.preparePresentationForTesting(title: "关于萤火虫", text: AboutUI.text(), allowsCopy: true,
      links: [InfoLink(title: "反馈问题", url: FeedbackUI.issuesURL)])
    InfoWindow.simulateOpenForTesting(FeedbackUI.issuesURL, succeeded: false)
    save(InfoWindow.renderSnapshotForTesting(appearance: appearance, minimum: true), "information-\(theme)")
    guard !candidate.permitsKeyboardFocusForTesting, !SettingsPanel.shared.isVisibleForTesting,
      !InfoWindow.isVisibleForTesting else { fail("nonactivation") }
}
// Invoke the production field action against the private configuration, including rollback.
SettingsPanel.shared.selectSectionForTesting(2)
guard let field = SettingsPanel.shared.rowForTesting("hotkey.toggle_mode"),
      field.commitTextForTesting("ctrl+shift+k"), ImeConfig.string("hotkey.toggle_mode") == "ctrl+shift+k",
      field.commitTextForTesting("banana"), ImeConfig.string("hotkey.toggle_mode") == "ctrl+shift+k",
      field.textValueForTesting == "ctrl+shift+k", SettingsPanel.shared.statusForTesting.hasPrefix("保存失败："),
      field.commitTextForTesting(""), ImeConfig.string("hotkey.toggle_mode") == "none",
      SettingsPanel.shared.statusForTesting.isEmpty
else { fail("real field action/save/rollback/disable") }
let primary = NSRect(x: 0, y: 0, width: 1920, height: 1080)
let secondary = NSRect(x: -1280, y: -200, width: 1280, height: 1024)
guard CandidateWindow.bestScreenIndex(for: NSRect(x: -800, y: 20, width: 2, height: 20), among: [primary,secondary]) == 1,
      CandidateWindow.bestScreenIndex(for: NSRect(x: 30, y: 30, width: 2, height: 20), among: [primary,secondary]) == 0
else { fail("screen selection") }
for area in [primary, secondary, NSRect(x: 80, y: -400, width: 320, height: 200)] {
    for point in [NSPoint(x: area.minX, y: area.minY), NSPoint(x: area.maxX, y: area.maxY)] {
        candidate.layout(at: NSRect(origin: point, size: NSSize(width: 2, height: 20)), within: area)
        guard area.contains(candidate.frame), candidate.candidateAccessibilityLabelsForTesting.count == 2 else { fail("edge/AX geometry") }
    }
}
let data = try JSONSerialization.data(withJSONObject: ["passed": true, "pairs": contrasts, "appearanceRequests": requests,
  "scope": "native light/dark colors and explicit production high-contrast color policy; not actual global high-contrast/VoiceOver"], options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("contrast.json"))
print("PASS appearance-contract: native light/dark plus high-contrast color policy, contrast pairs, bounded screen geometry, hidden views and candidate focus guard")
