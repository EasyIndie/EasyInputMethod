import Cocoa
import Darwin
import ime

@main
struct RenderPerformance {
    static func footprint() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1048576 : -1
    }

    static func main() {
        let args = CommandLine.arguments
        guard args.count == 3 || (args.count == 4 && ["--inspect-memory", "--stress"].contains(args[3])) else { fatalError("需要数据目录和隔离配置路径") }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        guard let screen = NSScreen.main else { fatalError("没有可用显示器，不能执行 GUI 性能检查") }
        guard args[2].withCString({ ime_config_init($0) }) == IME_OK else { fatalError("配置初始化失败") }
        let sessions = (0..<5).map { _ in
            ImeSession(wubiPath: args[1] + "/wubi86-core.tsv",
                pinyinCharsPath: args[1] + "/pinyin-chars.tsv",
                pinyinWordsPath: args[1] + "/pinyin-core.tsv")!
        }
        for session in sessions { session.prepare() }
        let area = screen.visibleFrame
        let caret = NSRect(x: area.midX, y: area.midY, width: 1, height: 20)
        let activationStart = DispatchTime.now().uptimeNanoseconds
        var window: CandidateWindow? = CandidateWindow()
        let activationMs = Double(DispatchTime.now().uptimeNanoseconds - activationStart) / 1e6
        print(String(format: "window_activation_ms=%.3f", activationMs))
        var samples: [Double] = []
        let rounds = args.count == 4 && args[3] == "--stress" ? 1000 : 100
        for round in 0..<rounds {
            for input in ["wq", "nihao", "zhongguo", "zz", "a", "kwwl"] {
                autoreleasepool {
                    let session = sessions[round % sessions.count]
                    session.reset()
                    for scalar in input.unicodeScalars {
                        autoreleasepool {
                            let start = DispatchTime.now().uptimeNanoseconds
                            _ = session.feed(scalar.value)
                            if session.isComposing {
                                if window == nil { window = CandidateWindow() }
                                window?.update(candidates: session.candidates(limit: 9).map { $0.text })
                                window?.show(at: caret)
                            } else { window?.hide() }
                            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6
                            samples.append(elapsed)
                            if elapsed >= 16 {
                                print(String(format: "slow_key round=%d input=%@ scalar=%u ms=%.3f",
                                    round + 1, input, scalar.value, elapsed))
                                fflush(stdout)
                            }
                        }
                    }
                    window?.hide()
                    // A GUI host drains its main loop between input sequences.
                    // Commit pending display transactions instead of accumulating them in this synchronous probe.
                    _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
                }
            }
            if rounds > 100 && round % 100 == 99 {
                print(String(format: "round=%d footprint_mib=%.2f", round + 1, footprint()))
                fflush(stdout)
            }
        }
        print("keys_at_or_above_16ms=\(samples.filter { $0 >= 16 }.count)")
        let cold = samples[0]
        let sorted = samples.dropFirst().sorted()
        print(String(format: "keys=%d cold_ms=%.3f warm_p95_ms=%.3f warm_max_ms=%.3f footprint_mib=%.2f",
            samples.count, cold, sorted[Int(Double(sorted.count - 1) * 0.95)], sorted.last!, footprint()))
        if args.count == 4 && args[3] == "--inspect-memory" {
            let inspect = Process()
            inspect.executableURL = URL(fileURLWithPath: "/usr/bin/vmmap")
            inspect.arguments = ["-summary", String(ProcessInfo.processInfo.processIdentifier)]
            do { try inspect.run(); inspect.waitUntilExit() }
            catch { fatalError("无法检查探针内存：\(error)") }
        }
        if args.count == 4 && args[3] == "--stress" {
            let inspect = Process()
            let output = Pipe()
            inspect.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
            inspect.arguments = ["-nP", "-a", "-p", String(ProcessInfo.processInfo.processIdentifier), "-i"]
            inspect.standardOutput = output
            do { try inspect.run(); inspect.waitUntilExit() }
            catch { fatalError("无法检查探针连接：\(error)") }
            let bytes = output.fileHandleForReading.readDataToEndOfFile()
            guard inspect.terminationStatus == 1 && bytes.isEmpty else {
                fatalError("探针网络检查未通过，状态\(inspect.terminationStatus)")
            }
            print("privacy_sample=passed: no IP sockets observed in isolated probe")
        }
        for session in sessions { session.focusOut() }
        window?.hide()
        // This measures synchronous FFI/layout/show, not IMK dispatch or compositor completion.
    }
}
