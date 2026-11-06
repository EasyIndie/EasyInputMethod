// 关闭指定应用里标题匹配的窗口（验收收尾用，报告231）。
// 用法：axclose <bundle-id> [标题子串]   —— 不给子串时只列出窗口，不动手。
// 只按 AXCloseButton 关窗，绝不 quit 应用、不碰其它窗口。
import AppKit
import ApplicationServices

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: axclose <bundle-id> [title-substring]")
    exit(2)
}
let bundleID = args[1]
let filter = args.count > 2 ? args[2] : nil

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("NO_APP \(bundleID)")
    exit(0)
}
let ax = AXUIElementCreateApplication(app.processIdentifier)
func attr(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
}
func text(_ element: AXUIElement, _ key: String) -> String {
    attr(element, key) as? String ?? ""
}

let windows = (attr(ax, kAXWindowsAttribute) as? [AXUIElement]) ?? []
var closed = 0
var kept: [String] = []
for window in windows {
    let title = text(window, kAXTitleAttribute)
    guard let filter else {
        print("WINDOW \(title)")
        continue
    }
    if !title.contains(filter) {
        kept.append(title)
        continue
    }
    if let raw = attr(window, kAXCloseButtonAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() {
        if AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString) == .success {
            closed += 1
            print("CLOSED \(title)")
        }
    }
}
print("RESULT closed=\(closed) kept=\(kept.count) app=\(bundleID)")
