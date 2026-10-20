// Test-only observer: record accessibility announcements and focus changes while the user types.
// Prints one JSON document at the end; never posts events itself.
import AppKit
import ApplicationServices
import Foundation

func fail(_ message: String) -> Never {
    fputs("BLOCKED：\(message)\n", stderr)
    exit(3)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, args[0] == "watch" else { fail("参数不符：watch <秒>") }
guard let seconds = Double(args[1]), seconds > 0, seconds <= 120 else { fail("时长无效") }

var events: [[String: Any]] = []
let lock = NSLock()

func attribute(_ element: AXUIElement, _ key: String) -> String {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return "" }
    return value as? String ?? ""
}

func record(_ kind: String, _ element: AXUIElement, _ info: [String: Any]) {
    var entry: [String: Any] = ["kind": kind,
                                "role": attribute(element, kAXRoleAttribute),
                                "label": attribute(element, kAXDescriptionAttribute),
                                "title": attribute(element, kAXTitleAttribute),
                                "at": ISO8601DateFormatter().string(from: Date())]
    if let announcement = info[NSAccessibility.NotificationUserInfoKey.announcement.rawValue as String] {
        entry["announcement"] = String(describing: announcement)
    }
    lock.lock()
    events.append(entry)
    lock.unlock()
}

var observer: AXObserver?
// 回调签名是 (AXObserver, AXUIElement, CFString, CFDictionary?)，直接按这个类型取。
let result = AXObserverCreateWithInfoCallback(getpid(), { _, element, notification, info, _ in
    let payload = (info as? [String: Any]) ?? [:]
    record(notification as String, element, payload)
}, &observer)
guard result == .success, let observer else { fail("无法创建 AX 观察器：\(result.rawValue)") }
let systemWide = AXUIElementCreateSystemWide()
for notification in [kAXAnnouncementRequestedNotification, kAXFocusedUIElementChangedNotification] {
    let status = AXObserverAddNotification(observer, systemWide, notification as CFString, nil)
    if status != .success && status != .notificationAlreadyRegistered {
        fputs("warn: 无法注册 \(notification)：\(status.rawValue)\n", stderr)
    }
}
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)

print("watching", seconds, "seconds", terminator: "\n")
fflush(stdout)
let deadline = Date().addingTimeInterval(seconds)
while Date() < deadline {
    CFRunLoopRunInMode(.defaultMode, 0.2, false)
}
if let data = try? JSONSerialization.data(withJSONObject: ["events": events], options: [.sortedKeys]),
   let text = String(data: data, encoding: .utf8) {
    print(text)
}
