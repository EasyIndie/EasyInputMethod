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
        guard args.count == 3 else { fatalError("需要数据目录和隔离配置路径") }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
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
        var window: CandidateWindow?
        var samples: [Double] = []
        for round in 0..<100 {
            for input in ["wq", "nihao", "zhongguo", "zz", "a", "kwwl"] {
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
                        samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
                    }
                }
                window?.hide()
            }
        }
        let cold = samples[0]
        let sorted = samples.dropFirst().sorted()
        print(String(format: "keys=%d cold_ms=%.3f warm_p95_ms=%.3f warm_max_ms=%.3f footprint_mib=%.2f",
            samples.count, cold, sorted[Int(Double(sorted.count - 1) * 0.95)], sorted.last!, footprint()))
        for session in sessions { session.focusOut() }
        window?.hide()
        // This measures synchronous FFI/layout/show, not IMK dispatch or compositor completion.
    }
}
