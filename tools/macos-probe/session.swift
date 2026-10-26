import CoreGraphics
import Foundation

// 会话状态探针：报告209 在 air 上被锁屏挡住整个验收（CGSSessionScreenIsLocked = 1），
// 但没有探针能提前判断，白等了半小时。这里只读 CGSessionCopyCurrentDictionary。
let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
func flag(_ key: String) -> Bool { (dictionary[key] as? Bool) ?? false }
let report: [String: Any] = [
    "locked": flag("CGSSessionScreenIsLocked"),
    "on_console": flag("kCGSSessionOnConsoleKey"),
    "user": dictionary["kCGSSessionUserNameKey"] as? String ?? "",
]
if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
    print(String(data: data, encoding: .utf8) ?? "{}")
} else {
    print("{}")
}
