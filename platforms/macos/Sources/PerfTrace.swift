import Foundation

/// 按键路径的内嵌计时（ADR-218）。
///
/// 只在测试进程启用：`LAMPYRIS_PERF_TRACE` 指向一个 JSONL 文件时，宿主把每次按键的
/// 引擎耗时与「到候选窗更新完成」的总耗时追加写入该文件。未设置时只有一次环境读取，
/// 后续走 Bool 短路，不改变任何产品行为。**不记录输入内容**，只记时长、候选数与是否提交。
final class PerfTrace {
    static let shared = PerfTrace()

    private var path: String?
    /// 分阶段时间点，调用方只在 enabled 时持有。
    enum Phase: String {
        case preedit = "preeditUs"
        case candidateData = "candidateDataUs"
        case status = "statusUs"
        case content = "contentUs"
        case caret = "caretUs"
        case window = "windowUs"
        case commit = "commitUs"
    }

    final class Marks {
        let start = DispatchTime.now()
        fileprivate var phases: [String: Double] = [:]
    }

    private init() {
        path = ProcessInfo.processInfo.environment["LAMPYRIS_PERF_TRACE"]
    }

    /// 隔离测试入口专用：读私有根里的标记文件再启用（宿由系统按需启动，环境变量常常注入不到）。
    /// 只在 `platforms/macos/tests/isolated-imk/main.swift` 里调用，产品路径不走这里。
    static func configureForTest(tracePath: String?) {
        guard shared.path == nil, let tracePath, !tracePath.isEmpty else { return }
        shared.path = tracePath
    }

    var enabled: Bool { path != nil }

    func begin() -> Marks? {
        guard enabled else { return nil }
        return Marks()
    }

    /// Attribute synchronous work only when this key has an active trace.
    func measure<T>(_ marks: Marks?, phase: Phase, _ work: () -> T) -> T {
        guard let marks else { return work() }
        let start = DispatchTime.now()
        let result = work()
        marks.phases[phase.rawValue, default: 0] += elapsedMicroseconds(from: start)
        return result
    }

    /// 引擎算完候选的时间点（还没画）。
    func stamp() -> DispatchTime? {
        enabled ? DispatchTime.now() : nil
    }

    /// 记录一次按键：engine 可为 nil（该分支没有单独的引擎阶段）。
    func finish(_ marks: Marks?, engine: DispatchTime?, candidates: Int, committed: Bool) {
        guard let marks, let path else { return }
        let total = elapsedMicroseconds(from: marks.start)
        let engineMicro = engine.map { elapsedMicroseconds(from: marks.start, to: $0) } ?? -1
        var record: [String: Any] = [
            "engineUs": engineMicro, "totalUs": total,
            "candidates": candidates, "committed": committed,
        ]
        if !marks.phases.isEmpty {
            record["phaseSchema"] = 1
            record["phases"] = marks.phases
        }
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
        else { return }
        data.append(0x0A)
        append(data, to: path)
    }

    /// 面板类动作（设置/关于）的打开耗时。
    func finishPanel(_ marks: Marks?, panel: String) {
        guard let marks, let path else { return }
        let line = String(
            format: "{\"panel\":\"%@\",\"totalUs\":%.1f}\n", panel,
            elapsedMicroseconds(from: marks.start))
        append(Data(line.utf8), to: path)
    }

    private func elapsedMicroseconds(from start: DispatchTime, to end: DispatchTime = DispatchTime.now())
        -> Double
    {
        Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1000
    }

    private func append(_ data: Data, to path: String) {
        let url = URL(fileURLWithPath: path)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
            // 首次创建时就收紧权限，避免把性能文件留在 0644。
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}
