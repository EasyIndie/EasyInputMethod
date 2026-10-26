// AX 树探针：打印指定 App 窗口的角色/标题/值/描述（浅层），用于判断辅助技术能否读到候选内容（报告203）。
// 用法：axdump [bundleID] [depth]（默认萤火虫，深度 2）
import AppKit
import ApplicationServices

func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}

func text(_ element: AXUIElement, _ key: String) -> String {
    if let value = attr(element, key) as? String { return value }
    if let value = attr(element, key) as? NSNumber { return value.stringValue }
    return ""
}

func describe(_ element: AXUIElement, depth: Int, maxDepth: Int) -> [[String: String]] {
    let row: [String: String] = [
        "role": text(element, kAXRoleAttribute),
        "subrole": text(element, kAXSubroleAttribute),
        "title": text(element, kAXTitleAttribute),
        "value": text(element, kAXValueAttribute),
        "desc": text(element, kAXDescriptionAttribute),
        "help": text(element, kAXHelpAttribute),
        "selected": text(element, kAXSelectedAttribute),
    ]
    var rows = [row.filter { !$0.value.isEmpty }]
    guard depth < maxDepth else { return rows }
    for child in (attr(element, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
        rows.append(contentsOf: describe(child, depth: depth + 1, maxDepth: maxDepth))
    }
    return rows
}

let bundle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "cn.jokerhub.inputmethod.Lampyris"
let maxDepth = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 2 : 2
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
    print("{\"windows\":[],\"reason\":\"not-running\"}")
    exit(1)
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(ax, 2)
var output: [[String: Any]] = []
for window in (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    output.append([
        "title": text(window, kAXTitleAttribute),
        "subrole": text(window, kAXSubroleAttribute),
        "tree": describe(window, depth: 0, maxDepth: maxDepth),
    ])
}
let payload: [String: Any] = ["pid": Int(app.processIdentifier), "windows": output]
let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
