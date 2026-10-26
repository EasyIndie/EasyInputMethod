// AX 通知观察器：注册 AXObserver 并打印目标 App 发出的通知（报告203）。
// 用来客观判断"选中项变化/上屏"时输入法有没有通知辅助技术——VoiceOver 只靠这些通知才能播报。
// 用法：axobserve [bundleID] [秒数] [深度=4]
import AppKit
import ApplicationServices

let bundle = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "cn.jokerhub.inputmethod.Lampyris"
let seconds = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2]) ?? 10 : 10
// 播报常常发在深层元素上（如候选文档视图），深度要够（报告206）。
let maxDepth = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3]) ?? 4 : 4
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else {
    print("{\"reason\":\"not-running\"}")
    exit(1)
}
let pid = app.processIdentifier
var events: [[String: Any]] = []
let started = Date()

func callback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    var role: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
    var description: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &description)
    events.append([
        "t": round(Date().timeIntervalSince(started) * 1000) / 1000,
        "notification": notification as String,
        "role": (role as? String) ?? "?",
        "desc": (description as? String) ?? "",
    ])
}

var observer: AXObserver?
guard AXObserverCreate(pid, callback, &observer) == .success, let observer else {
    print("{\"reason\":\"observer-create-failed\"}")
    exit(1)
}

let notifications = [
    kAXFocusedUIElementChangedNotification,
    kAXSelectedChildrenChangedNotification,
    kAXValueChangedNotification,
    kAXTitleChangedNotification,
    kAXCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXLayoutChangedNotification,
    kAXAnnouncementRequestedNotification,
]

func observe(_ element: AXUIElement, depth: Int) {
    for name in notifications {
        AXObserverAddNotification(observer, element, name as CFString, nil)
    }
    guard depth < maxDepth else { return }
    var raw: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &raw) == .success,
          let children = raw as? [AXUIElement] else { return }
    for child in children { observe(child, depth: depth + 1) }
}

observe(AXUIElementCreateApplication(pid), depth: 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
let payload: [String: Any] = ["pid": Int(pid), "seconds": seconds, "count": events.count, "events": events]
let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
