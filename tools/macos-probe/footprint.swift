import Darwin
import Foundation

/// 打印某个进程的 physical footprint（MiB），不挂起目标进程（报告 331 / ADR-389）。
///
/// 为什么不用 `vmmap -summary`：`vmmap` 会 task_suspend 目标再走一遍地址空间，实测把宿主的
/// 按键延迟从 15–30 ms 抬到 300–600 ms（10/10 轮），久用探针因此会把自己量成"卡顿"。
/// `proc_pid_rusage(RUSAGE_INFO_V4)` 只读内核记账，不暂停进程。
///
/// 用法：`footprint <pid> [more pids…]` → 每行一个 MiB 数值（保留一位小数）。

func physicalFootprintBytes(pid: pid_t) -> UInt64? {
    var info = rusage_info_current()
    let result = withUnsafeMutablePointer(to: &info) { pointer -> Int32 in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
            proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, rebound)
        }
    }
    guard result == 0 else { return nil }
    return info.ri_phys_footprint
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard !arguments.isEmpty else {
    FileHandle.standardError.write(Data("usage: footprint <pid> [pid…]\n".utf8))
    exit(2)
}

var failed = false
for argument in arguments {
    guard let pid = pid_t(argument), let bytes = physicalFootprintBytes(pid: pid) else {
        FileHandle.standardError.write(Data("footprint: 无法读取 \(argument)\n".utf8))
        failed = true
        continue
    }
    let mebibytes = Double(bytes) / 1_048_576
    print(String(format: "%.1f", mebibytes))
}
exit(failed ? 1 : 0)
