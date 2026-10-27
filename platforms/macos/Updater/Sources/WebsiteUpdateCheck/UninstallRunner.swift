import AppKit
import Foundation
import LampyrisInstallCore

/// AppKit 侧的卸载环境：把「停进程 / 切回 ABC / 自删除」接到共享核心（ADR-296）。
///
/// 共享核心只依赖 Foundation，进程与输入源操作留在这里；更新窗口与 `--uninstall` 共用。
enum UninstallRunner {
    static func run(mode: UninstallMode, paths: UninstallPaths, selfBundle: URL) throws
        -> UninstallOutcome
    {
        try UninstallerCore.run(mode: mode, paths: paths, selfBundle: selfBundle,
                                stopApps: stop, switchToABCAndDisable: switchToABC)
    }

    /// 自卸载：调度 detached `/bin/sh` 在进程退出后删除本体。
    @discardableResult
    static func scheduleSelfRemoval(_ paths: [String]) -> Bool {
        UninstallerCore.scheduleSelfRemoval(paths: paths)
    }

    private static func stop(_ identifiers: [String]) {
        for identifier in identifiers {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            for application in running where !application.isTerminated {
                application.terminate()
            }
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline && running.contains(where: { !$0.isTerminated }) {
                usleep(100_000)
            }
            for application in running where !application.isTerminated {
                application.forceTerminate()
            }
        }
    }

    private static func switchToABC(_ helper: URL) {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        for command in [["switch-abc"], ["disable", UninstallIdentifiers.host]] {
            let process = Process()
            process.executableURL = helper
            process.arguments = command
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}
