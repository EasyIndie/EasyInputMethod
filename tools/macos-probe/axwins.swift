// AX 窗口几何探针：列出指定 bundle 的窗口位置/尺寸/角色，用于多屏验收判定候选窗与 HUD 落点。
// macOS 13 上 HUD 可能不在 AX 树里；此时本探针会给不出窗口，需用截图佐证（报告 202）。
// 用法：axwins [bundleID]（默认萤火虫）。
import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ key: String) -> String {
    if let value = attr(element, key) as? String { return value }
    return ""
}

func point(_ element: AXUIElement, _ key: String) -> CGPoint? {
    guard let value = attr(element, key), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
}

func size(_ element: AXUIElement, _ key: String) -> CGSize? {
    guard let value = attr(element, key), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}

let bundle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "cn.jokerhub.inputmethod.Lampyris"
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
    print("{\"windows\":[],\"reason\":\"not-running\"}")
    exit(1)
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax, 2)
var items: [[String: Any]] = []
for window in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    var item: [String: Any] = [
        "title": text(window, kAXTitleAttribute),
        "role": text(window, kAXRoleAttribute),
        "subrole": text(window, kAXSubroleAttribute),
    ]
    if let position = point(window, kAXPositionAttribute) { item["x"] = position.x; item["y"] = position.y }
    if let frame = size(window, kAXSizeAttribute) { item["w"] = frame.width; item["h"] = frame.height }
    items.append(item)
}
let payload: [String: Any] = ["pid": Int(app.processIdentifier), "windows": items]
let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
