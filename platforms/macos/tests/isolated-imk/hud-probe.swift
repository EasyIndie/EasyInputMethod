// Bounded test helper: enumerate and capture windows of the owned isolated input method host only.
import AppKit
import Cocoa
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    fputs("BLOCKED：\(message)\n", stderr)
    exit(3)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2, ["windows", "capture"].contains(args[0]) else { fail("参数不符") }
let root = URL(fileURLWithPath: args[1]).standardizedFileURL
let prefix = "lampyris-imk-"
let fm = FileManager.default
guard root.lastPathComponent.hasPrefix(prefix), UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil,
      (try? String(contentsOf: root.appendingPathComponent("owner"), encoding: .utf8)) == root.lastPathComponent,
      let attributes = try? fm.attributesOfItem(atPath: root.path),
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
else { fail("独有目录身份不符") }
var identity = "cn.jokerhub.inputmethod.LampyrisIMKTest." + String(root.lastPathComponent.dropFirst(prefix.count))
// 对照实验专用：只允许指向生产身份的宿主，用来判断「面板不可见」是产品行为还是隔离环境行为。
if let index = args.firstIndex(of: "--host-bundle") {
    guard args.count > index + 1 else { fail("--host-bundle 缺参数") }
    guard args[index + 1] == "cn.jokerhub.inputmethod.Lampyris" else { fail("对照宿主只允许生产身份") }
    identity = args[index + 1]
}
guard let host = NSRunningApplication.runningApplications(withBundleIdentifier: identity).first else {
    fail("宿主未运行：\(identity)")
}

// CGWindowList reports top-left-origin rectangles; convert to AppKit (bottom-left origin) before
// comparing against NSScreen frames, otherwise the displays are mis-assigned on stacked layouts.
let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
func appKitRect(_ frame: CGRect) -> CGRect {
    CGRect(x: frame.origin.x, y: primaryHeight - frame.origin.y - frame.height,
           width: frame.width, height: frame.height)
}
func screenIndex(_ frame: CGRect) -> Int? {
    let rect = appKitRect(frame)
    for (index, screen) in NSScreen.screens.enumerated() where screen.frame.intersects(rect) { return index }
    return nil
}
let windows = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
    .filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == host.processIdentifier }
    .compactMap { info -> [String: Any]? in
        guard let number = info[kCGWindowNumber as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return ["number": number,
                "name": info[kCGWindowName as String] as? String ?? "",
                "layer": info[kCGWindowLayer as String] as? Int ?? 0,
                "alpha": info[kCGWindowAlpha as String] as? Double ?? 0,
                "onScreen": info[kCGWindowIsOnscreen as String] as? Bool ?? false,
                "x": rect.origin.x, "y": rect.origin.y, "width": rect.width, "height": rect.height,
                "screen": screenIndex(rect) as Any]
    }
    .sorted { (($0["number"] as? Int) ?? 0) < (($1["number"] as? Int) ?? 0) }
let screens = NSScreen.screens.enumerated().map { index, screen -> [String: Any] in
    ["index": index, "x": screen.frame.origin.x, "y": screen.frame.origin.y,
     "width": screen.frame.width, "height": screen.frame.height,
     "scale": screen.backingScaleFactor,
     "axX": screen.frame.origin.x, "axY": primaryHeight - screen.frame.origin.y - screen.frame.height]
}
let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
var result: [String: Any] = ["pid": Int(host.processIdentifier), "bundle": identity,
                            "frontmost": frontmost, "screens": screens, "windows": windows]

if args[0] == "capture" {
    guard args.count >= 3 else { fail("capture 需要输出目录") }
    let directory = URL(fileURLWithPath: args[2]).standardizedFileURL
    func canonical(_ path: String) -> String {
        path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
    }
    guard canonical(directory.path).hasPrefix(canonical(root.path) + "/") else { fail("截图目录不在独有根内") }
    try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    // 可显式点名窗口（HUD 存活仅 1.15s，重枚举常常已经太晚），否则只拍当前在屏窗口。
    let explicit = args.dropFirst(3).compactMap { Int($0) }
    var shots: [[String: Any]] = []
    for window in windows where explicit.isEmpty ? (window["onScreen"] as? Bool) == true
                                  : explicit.contains((window["number"] as? Int) ?? -1) {
        guard let number = window["number"] as? Int,
              let width = window["width"] as? Double, let height = window["height"] as? Double,
              width >= 8, height >= 8 else { continue }
        let name = "window-\(number)-\(Int(width))x\(Int(height)).png"
        let file = directory.appendingPathComponent(name)
        // Our own process has no screen-recording grant; the Apple-signed screencapture can read windows.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-o", "-l", String(number), file.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch { continue }
        guard process.terminationStatus == 0,
              let size = (try? fm.attributesOfItem(atPath: file.path))?[.size] as? Int, size > 0 else { continue }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        shots.append(["number": number, "file": name, "bytes": size])
    }
    result["captures"] = shots
}
guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8) else { fail("无法输出窗口状态") }
print(text)
