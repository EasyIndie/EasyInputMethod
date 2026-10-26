// 窗口几何探针：按 owner 名/进程列出 CGWindow 的 layer/bounds，用于判定候选窗与 HUD 的落点（macOS 13 的 HUD 不在 AX 树里）。
// 用法：cgwins [owner 子串]（默认 Lampyris）；输出 JSON。
import AppKit

let wanted = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lampyris"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
var items: [[String: Any]] = []
if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    for window in list {
        let owner = window[kCGWindowOwnerName as String] as? String ?? ""
        guard owner.localizedCaseInsensitiveContains(wanted) else { continue }
        let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
        items.append([
            "owner": owner,
            "pid": window[kCGWindowOwnerPID as String] as? Int ?? 0,
            "layer": window[kCGWindowLayer as String] as? Int ?? 0,
            "name": window[kCGWindowName as String] as? String ?? "",
            "bounds": [bounds["X"] ?? 0, bounds["Y"] ?? 0, bounds["Width"] ?? 0, bounds["Height"] ?? 0] as [CGFloat],
        ])
    }
}
let data = try? JSONSerialization.data(withJSONObject: ["windows": items], options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
