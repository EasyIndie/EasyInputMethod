import Foundation

/// Developer ID candidate validation and exact executable stop for the selected target.
public enum DefaultInstallEnvironment {
    /// 替换前是否需要停掉正在运行的同类实例。
    ///
    /// **更新程序自更新时不能停**（ADR-306）：执行自更新的进程正是它自己，
    /// `stopHost` 会把当前进程 SIGTERM 掉，安装事务停在「宿主已换、回执未写」的半路，
    /// 留下 staging 与缺失的 receipt。运行中的 bundle 允许被 rename 替换（旧 inode 继续服务），
    /// 下次启动自然用新版，这正是 ADR-295 说的「运行中的实例保持不动」。
    public static func stopsRunningInstance(_ target: InstallTarget) -> Bool {
        target.identity != InstallTarget.updater.identity
    }

    public static func make(target: InstallTarget = .production) -> InstallEnvironment {
        InstallEnvironment(validateCandidate: { app in
            let executable = app.appendingPathComponent(target.executablePath)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw InstallError.candidateInvalid("缺少可执行文件")
            }
            let plist = app.appendingPathComponent("Contents/Info.plist").path
            let identity = run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleIdentifier", plist])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard identity == target.identity else {
                throw InstallError.candidateInvalid("标识不符：\(identity)")
            }
            let executableName = run("/usr/libexec/PlistBuddy", ["-c", "Print :CFBundleExecutable", plist])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard executableName == executable.lastPathComponent else {
                throw InstallError.candidateInvalid("可执行文件身份不符：\(executableName)")
            }
            try require("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path])
            let details = run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path], stderr: true)
            guard details.contains("Authority=Developer ID Application:"), details.contains("runtime") else {
                throw InstallError.candidateInvalid("缺少 Developer ID 或 hardened runtime")
            }
            try requireTicket(app)
            // Gatekeeper 是最终裁决：票据装订过就必须能离线通过（ADR-390）。
            try require("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path],
                        failure: "Gatekeeper 未接受该应用（缺少公证票据或签名无效）")
        }, stopHost: { executable in
            guard stopsRunningInstance(target) else { return }
            let holders = run("/usr/sbin/lsof", ["-t", executable.path])
            for value in holders.split(whereSeparator: { $0.isWhitespace }) {
                guard let pid = Int32(value) else { continue }
                let command = run("/bin/ps", ["-p", String(pid), "-o", "comm="]).trimmingCharacters(in: .whitespacesAndNewlines)
                if command == executable.path {
                    kill(pid, SIGTERM)
                }
            }
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let remaining = run("/usr/sbin/lsof", ["-t", executable.path])
                let stillHeld = remaining.split(whereSeparator: { $0.isWhitespace }).contains { value in
                    guard let pid = Int32(value) else { return false }
                    return run("/bin/ps", ["-p", String(pid), "-o", "comm="])
                        .trimmingCharacters(in: .whitespacesAndNewlines) == executable.path
                }
                if !stillHeld { return }
                Thread.sleep(forTimeInterval: 0.1)
            }
            throw InstallError.hostStopFailed("宿主未退出")
        })
    }

    /// 公证票据（`stapler` 装订物）落在 bundle 的 `Contents/CodeResources`。
    ///
    /// 不调用 `xcrun stapler validate`：`xcrun` 只在装了 Command Line Tools 的机器上可用，
    /// 普通帐户的 Mac 上没有它就是"校验失败"，一次正常安装会被判成候选不合格（报告 332）。
    /// 票据内容是否被 Apple 认可不在这里解析，交给下面的 `spctl`（离线只认票据）。
    private static func requireTicket(_ app: URL) throws {
        let ticket = app.appendingPathComponent("Contents/CodeResources")
        let attributes = try? FileManager.default.attributesOfItem(atPath: ticket.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            throw InstallError.candidateInvalid("缺少公证票据（未装订公证）")
        }
    }

    private static func run(_ tool: String, _ arguments: [String], stderr: Bool = false) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = stderr ? FileHandle.nullDevice : pipe
        process.standardError = stderr ? pipe : FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func require(_ tool: String, _ arguments: [String], failure: String? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw InstallError.candidateInvalid(tool) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.candidateInvalid(failure ?? "\(tool) 校验失败")
        }
    }
}
