// 键入探针：在自己的进程内切输入源并合成按键，读回文本，用于自动化「键入路径」验收。
// 之所以必须自建窗口：`TISSelectInputSource` 只影响调用进程自己的输入上下文，
// 从外部进程切源后往别的 App 发键只会落成裸 ASCII（报告 187）。
// 仅开发/验收使用，不进入产品。
import AppKit
import Carbon

let keys: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31,
    "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    " ": 49, ".": 47, ",": 43,
]

func argument(_ name: String, default fallback: String) -> String {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name), index + 1 < args.count else { return fallback }
    return args[index + 1]
}

struct SourceID {
    static func find(_ wanted: String) -> TISInputSource? {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
        return list.first { source in
            guard let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            return (Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String) == wanted
        }
    }
}

final class Harness: NSObject, NSApplicationDelegate {
    private let source = argument("--source", default: "com.apple.keylayout.ABC")
    private let text = argument("--keys", default: "wq")
    private let settle = Double(argument("--settle", default: "1.2")) ?? 1.2
    private let out = argument("--out", default: "")
    private let delay = Double(argument("--delay", default: "1.0")) ?? 1.0
    private let tap = argument("--tap", default: "session")
    private let window = NSWindow(contentRect: NSRect(x: 240, y: 240, width: 420, height: 140),
                                  styleMask: [.titled], backing: .buffered, defer: false)
    private let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 140))

    func applicationDidFinishLaunching(_ notification: Notification) {
        view.isEditable = true
        view.isSelectable = true
        view.isRichText = false
        view.drawsBackground = true
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        view.window?.makeFirstResponder(view)
        var report: [String: Any] = ["requested_source": source, "keys_seen": 0]
        var seen = 0
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            seen += 1
            report["keys_seen"] = seen
            return event
        }
        if let target = SourceID.find(source) {
            report["select_rc"] = Int(TISSelectInputSource(target))
        } else {
            report["select_rc"] = "missing-source"
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + self.delay) {
            report["app_active"] = NSApp.isActive
            report["window_key"] = self.window.isKeyWindow
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            let property = TISGetInputSourceProperty(current, kTISPropertyInputSourceID)
            report["current_source"] = property.map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
            let target: CGEventTapLocation = self.tap == "hid" ? .cghidEventTap : .cgSessionEventTap
            report["tap"] = self.tap
            let selfPID = ProcessInfo.processInfo.processIdentifier
            let eventSource = CGEventSource(stateID: .hidSystemState)
            for character in self.text {
                guard let code = keys[character] else { continue }
                let down = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: true)
                let up = CGEvent(keyboardEventSource: eventSource, virtualKey: code, keyDown: false)
                down?.flags = []
                up?.flags = []
                if self.tap == "self" { down?.postToPid(selfPID) } else { down?.post(tap: target) }
                usleep(120_000)
                if self.tap == "self" { up?.postToPid(selfPID) } else { up?.post(tap: target) }
                usleep(180_000)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + self.settle) {
                let output = self.view.string
                report["text"] = output
                report["has_non_ascii"] = output.unicodeScalars.contains { $0.value > 0x7E }
                report["length"] = output.count
                let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
                let json = String(data: data ?? Data(), encoding: .utf8) ?? "{}"
                if self.out.isEmpty { print(json) } else { try? json.write(toFile: self.out, atomically: true, encoding: .utf8) }
                NSApp.terminate(nil)
            }
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let harness = Harness()
app.delegate = harness
app.run()
