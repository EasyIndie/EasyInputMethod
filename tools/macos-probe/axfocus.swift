// 读取当前前台应用焦点元素的 AX 角色与文本，用于跨客户端验收（TextEdit/浏览器/终端/Xcode 通用）。
import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ key: String) -> String {
    if let value = attr(element, key) as? String { return value }
    if let number = attr(element, key) as? NSNumber { return number.stringValue }
    return ""
}

guard let app = NSWorkspace.shared.frontmostApplication else { print("NO_FRONTMOST"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
func element(_ key: String) -> AXUIElement? {
    guard let value = attr(ax, key), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
}
let focused = element(kAXFocusedUIElementAttribute) ?? element(kAXFocusedWindowAttribute)
guard let element = focused else { print("NO_FOCUS_PID=\(app.processIdentifier)"); exit(1) }
var report: [String: Any] = [
    "app": app.localizedName ?? "?",
    "pid": Int(app.processIdentifier),
    "role": text(element, kAXRoleAttribute),
    "value": text(element, kAXValueAttribute),
    "selected": text(element, kAXSelectedTextAttribute),
]
if let range = attr(element, kAXSelectedTextRangeAttribute) {
    report["has_range"] = CFGetTypeID(range) == AXValueGetTypeID()
}
let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
