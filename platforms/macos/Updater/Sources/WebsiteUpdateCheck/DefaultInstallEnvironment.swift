import Foundation

/// 生产环境的候选校验与宿主停止：与 packaging/macos/upgrade.py 的守卫一致。
enum DefaultInstallEnvironment {
    static func make() -> InstallEnvironment {
        InstallEnvironment(validateCandidate: { app in
            let executable = app.appendingPathComponent(UpdateInstaller.executablePath)
            guard FileManager.default.isExecutableFile(atPath: executable.path) else {
                throw InstallError.candidateInvalid("缺少可执行文件")
            }
            let identity = run("/usr/libexec/PlistBuddy",
                               ["-c", "Print :CFBundleIdentifier",
                                app.appendingPathComponent("Contents/Info.plist").path])
            guard identity == UpdateInstaller.identity else {
                throw InstallError.candidateInvalid("标识不符：\(identity)")
            }
            try require("/usr/bin/codesign", ["--verify", "--strict", "--deep", app.path])
            let details = run("/usr/bin/codesign", ["-dv", "--verbose=4", app.path], stderr: true)
            guard details.contains("Authority=Developer ID Application:"), details.contains("runtime") else {
                throw InstallError.candidateInvalid("缺少 Developer ID 或 hardened runtime")
            }
            try require("/usr/bin/xcrun", ["stapler", "validate", app.path])
            try require("/usr/sbin/spctl", ["--assess", "--type", "execute", app.path])
        }, stopHost: { executable in
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

    private static func require(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw InstallError.candidateInvalid(tool) }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.candidateInvalid("\(tool) 校验失败")
        }
    }
}
