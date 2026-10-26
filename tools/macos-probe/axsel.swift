import AppKit
import ApplicationServices

// ADR-291 取证：打印候选容器暴露的 AXSelectedChildren，以及每个候选项的选中状态。
// `AXAnnouncementRequested` 只投递给辅助技术（VoiceOver），探针收不到；能收到的客观信号是
// `AXSelectedChildren` 的内容 + `.selectedChildrenChanged` 通知（报告206/207）。
func attr(_ e: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, k as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ k: String) -> String { attr(e, k) as? String ?? "" }
func kids(_ e: AXUIElement, _ k: String) -> [AXUIElement] {
    (attr(e, k) as? [AXUIElement]) ?? []
}
func find(_ e: AXUIElement, role: String, depth: Int) -> AXUIElement? {
    if str(e, kAXRoleAttribute) == role { return e }
    guard depth > 0 else { return nil }
    for c in kids(e, kAXChildrenAttribute) {
        if let hit = find(c, role: role, depth: depth - 1) { return hit }
    }
    return nil
}

let args = CommandLine.arguments
guard args.count > 1, let app = NSRunningApplication.runningApplications(withBundleIdentifier: args[1]).first else {
    print("NO_APP"); exit(1)
}
let owner = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(owner, 2)
var report: [String: Any] = ["pid": Int(app.processIdentifier)]
var found: [String] = []
// 候选容器是滚动区里的 group（ADR-291 在它上面暴露 AXSelectedChildren）。
func selectedOf(_ e: AXUIElement) -> (String, [String], [Bool]) {
    let selected = kids(e, kAXSelectedChildrenAttribute)
    let flags = kids(e, kAXChildrenAttribute).map { (attr($0, kAXSelectedAttribute) as? Bool) ?? false }
    return (str(e, kAXRoleAttribute), selected.map { str($0, kAXDescriptionAttribute) }, flags)
}
var windows: [[String: Any]] = []
for window in kids(owner, kAXWindowsAttribute) {
    let subrole = str(window, kAXSubroleAttribute)
    found.append(subrole)
    var nodes: [[String: Any]] = []
    if let scroll = find(window, role: kAXScrollAreaRole, depth: 4) {
        var entries: [(String, [String], [Bool])] = [selectedOf(scroll)]
        for child in kids(scroll, kAXChildrenAttribute) { entries.append(selectedOf(child)) }
        nodes = entries.map { ["role": $0.0, "selected": $0.1, "flags": $0.2] as [String: Any] }
    }
    windows.append(["subrole": subrole, "nodes": nodes])
}
report["windowNodes"] = windows
report["windows"] = found
if found.isEmpty { print("NO_PANEL") }
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(data: data, encoding: .utf8) ?? "{}")
