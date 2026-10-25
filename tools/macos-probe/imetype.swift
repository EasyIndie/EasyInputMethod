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
    private let selfPost = CommandLine.arguments.contains("--self-post")
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
        var emitted = false
        var lastKeyAt = Date()
        let emit: () -> Void = {
            let output = self.view.string
            report["text"] = output
            report["has_non_ascii"] = output.unicodeScalars.contains { $0.value > 0x7E }
            report["length"] = output.count
            let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let json = String(data: data ?? Data(), encoding: .utf8) ?? "{}"
            if self.out.isEmpty { print(json) } else { try? json.write(toFile: self.out, atomically: true, encoding: .utf8) }
            // 写完后多留 0.8 秒，给仍在投递中的按键留落点，不瞬退把余键送给别的应用（报告199）。
            // 只用 exit(0)：NSApp.terminate 在 macOS 13 上会卡在 NSQuietSafeQuit（sample 可见），残留实例会抢前台。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { exit(0) }
        }
        // 报告198/199：读出口从「最后一个按键」起算（静默 settle 秒），而不是从启动起算，否则慢机器上尾部按键会落在读出口之后。
        // 用轮询静默判定而不用定时器取消：按键持续不断时也不会永远不落盘，且 settle+30 秒后无论如何都落盘。
        func startReadout() {
            let started = Date()
            lastKeyAt = started
            let timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { timer in
                guard !emitted else { timer.invalidate(); return }
                let idle = Date().timeIntervalSince(lastKeyAt)
                let total = Date().timeIntervalSince(started)
                guard idle >= self.settle || total >= self.settle + 30 else { return }
                emitted = true
                timer.invalidate()
                emit()
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        _ = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            seen += 1
            report["keys_seen"] = seen
            lastKeyAt = Date()
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
            if self.selfPost {
                self.runSelfPost(report: &report)
                return
            }
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
            startReadout()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let harness = Harness()
app.delegate = harness
app.run()

extension Harness {
    /// 自投递：把 NSEvent 直接交给测试窗口的 keyDown（经输入上下文走真实 IME 往返），
    /// 用文本变更通知记录「投递→文本变化」用时；不轮询字符串，避免测自己（报告191）。
    func runSelfPost(report: inout [String: Any]) {
        var latencies: [Double] = []
        var postedAt = DispatchTime.now()
        let observer = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: view, queue: nil) { _ in
                let us = Double(DispatchTime.now().uptimeNanoseconds - postedAt.uptimeNanoseconds) / 1000
                latencies.append(us)
            }
        for character in text {
            guard let code = keys[character] else { continue }
            let windowNumber = view.window?.windowNumber ?? 0
            let chars = String(character)
            guard let down = NSEvent.keyEvent(
                    with: .keyDown, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                    context: nil, characters: chars, charactersIgnoringModifiers: chars,
                    isARepeat: false, keyCode: code),
                  let up = NSEvent.keyEvent(
                    with: .keyUp, location: .zero, modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: windowNumber,
                    context: nil, characters: chars, charactersIgnoringModifiers: chars,
                    isARepeat: false, keyCode: code) else { continue }
            postedAt = DispatchTime.now()
            view.keyDown(with: down)
            view.keyUp(with: up)
            let deadline = Date(timeIntervalSinceNow: 0.08)
            while Date() < deadline { RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.004)) }
        }
        NotificationCenter.default.removeObserver(observer)
        let sorted = latencies.sorted()
        func pct(_ p: Double) -> Double {
            guard !sorted.isEmpty else { return 0 }
            return (sorted[min(sorted.count - 1, Int((p / 100 * Double(sorted.count - 1)).rounded()))] / 10).rounded() / 100
        }
        report["latency_ms"] = ["p50": pct(50), "p95": pct(95), "max": pct(100), "count": sorted.count] as [String: Any]
        report["latencies_ms"] = sorted.map { ($0 / 10).rounded() / 100 }
        report["text"] = view.string
        report["has_non_ascii"] = view.string.unicodeScalars.contains { $0.value > 0x7E }
        finish(report: report)
    }

    func finish(report: [String: Any]) {
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        let json = String(data: data ?? Data(), encoding: .utf8) ?? "{}"
        if out.isEmpty { print(json) } else { try? json.write(toFile: out, atomically: true, encoding: .utf8) }
        NSApp.terminate(nil)
    }
}
