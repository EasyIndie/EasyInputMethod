import Foundation

/// 卸载：把「切回 ABC → 停进程 → 删/保留数据 → 残留复查 → （可选）自删除」放在一处，
/// 供 DMG 卸载器与已安装的更新程序共用（ADR-296）。
///
/// 纯逻辑部分（`plan` / `selfRemovalScript`）不做 IO，便于离线回归。
public enum UninstallMode: Sendable, Equatable {
    /// 保留 `config.toml` 与个人词库，其余（应用、更新程序、更新备份、缓存）全部删除。
    case keepData
    /// 连配置与词库一起删除。
    case removeAll
}

public struct UninstallPaths: Sendable {
    public let home: URL
    /// `~/Library/Input Methods`（或隔离根内的同名目录）。
    public let domain: URL
    /// `~/Applications`：更新程序所在目录；隔离构建传 nil，绝不碰真实目录。
    public let applications: URL?
    public let support: URL

    public init(home: URL, domain: URL, applications: URL?, support: URL) {
        self.home = home
        self.domain = domain
        self.applications = applications
        self.support = support
    }

    /// 生产路径（与安装/更新使用同一组常量）。
    public static func production(home: URL = FileManager.default.homeDirectoryForCurrentUser)
        -> UninstallPaths
    {
        UninstallPaths(home: home,
                       domain: home.appendingPathComponent("Library/Input Methods"),
                       applications: home.appendingPathComponent("Applications"),
                       support: home.appendingPathComponent("Library/Application Support/Lampyris"))
    }

    public var hostBundle: URL { domain.appendingPathComponent(InstallTarget.production.bundleName) }
    public var supportDirectory: URL { support }
}

public enum UninstallIdentifiers {
    public static let host = "cn.jokerhub.inputmethod.Lampyris"
    public static let updater = "cn.jokerhub.Lampyris.WebsiteUpdateCheck"
    public static let installer = "cn.jokerhub.Lampyris.Installer"
    public static let uninstaller = "cn.jokerhub.Lampyris.Uninstaller"
    /// 用户数据里永远保留的两份文件（keepData 模式）。
    public static let userFiles = ["config.toml", "user-dictionary.tsv"]
}

public enum UninstallError: LocalizedError, Equatable {
    case invalidApp
    case residual([String])

    public var errorDescription: String? {
        switch self {
        case .invalidApp: return "当前安装不是萤火虫输入法，已停止。"
        case .residual(let paths): return "仍有文件未能删除：\n" + paths.joined(separator: "\n")
        }
    }
}

public struct UninstallOutcome: Sendable, Equatable {
    public let kept: [String]
    public let removedCount: Int
    /// 需要在进程退出后由 detached shell 删除的路径（自卸载时为更新程序本体）。
    public let pendingSelfRemoval: [String]
}

/// 一次卸载的完整计划：要删的路径、要保留的文件、需要延后删除的自删除路径。
public struct UninstallPlan: Sendable, Equatable {
    public let targets: [String]
    public let kept: [String]
    public let pendingSelfRemoval: [String]
    public let removeSupport: Bool
}

public enum UninstallerCore {
    /// 更新程序按 bundle id 定位（ADR-294）；同时保留历史目录名以便清理。
    public static func locateUpdaters(applications: URL?) -> [URL] {
        guard let applications else { return [] }
        let legacy = applications.appendingPathComponent("Lampyris Update.app")
        var found: [URL] = []
        let children = (try? FileManager.default.contentsOfDirectory(
            at: applications, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for child in children where child.pathExtension == "app" {
            guard identifier(at: child) == UninstallIdentifiers.updater else { continue }
            found.append(applications.appendingPathComponent(child.lastPathComponent))
        }
        if !found.contains(legacy) { found.append(legacy) }
        return found
    }

    /// 隐藏的临时/备份目录（`.lampyris-install-*`、`.lampyris-updater-backup-*`）一并清理。
    public static func stagingLeftovers(applications: URL?, domains: [URL]) -> [URL] {
        var leftovers: [URL] = []
        var directories = domains
        if let applications { directories.append(applications) }
        for directory in directories {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for child in children where child.lastPathComponent.hasPrefix(".lampyris-") {
                leftovers.append(directory.appendingPathComponent(child.lastPathComponent))
            }
        }
        return leftovers
    }

    /// 直接读 Info.plist 取标识：不依赖 LaunchServices/Bundle 的加载语义，离线可测。
    public static func identifier(at app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    public static func isProductionApp(_ app: URL) -> Bool {
        identifier(at: app) == UninstallIdentifiers.host
    }

    /// 计算删除清单。`selfBundle` 是被卸载掉的调用方自己的 bundle（自卸载时非空）：
    /// 它不能在自己还运行时被删除，只能进 `pendingSelfRemoval`。
    public static func plan(mode: UninstallMode, paths: UninstallPaths, selfBundle: URL? = nil,
                            isInstalled: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) })
        throws -> UninstallPlan
    {
        let fileManager = FileManager.default
        let host = paths.hostBundle
        if isInstalled(host) && !isProductionApp(host) { throw UninstallError.invalidApp }

        var targets: [URL] = [host,
                              paths.home.appendingPathComponent("Library/Application Support/Lampyris-install-backups"),
                              paths.home.appendingPathComponent(
                                  "Library/Application Scripts/\(UninstallIdentifiers.host)")]
        let updaters = locateUpdaters(applications: paths.applications)
        let staging = stagingLeftovers(applications: paths.applications,
                                       domains: [paths.domain, paths.support])
        targets.append(contentsOf: updaters)
        targets.append(contentsOf: staging)
        for identifier in [UninstallIdentifiers.host, UninstallIdentifiers.updater,
                           UninstallIdentifiers.installer] {
            targets.append(paths.home.appendingPathComponent("Library/Caches/\(identifier)"))
            targets.append(paths.home.appendingPathComponent("Library/Preferences/\(identifier).plist"))
            targets.append(paths.home.appendingPathComponent(
                "Library/Saved Application State/\(identifier).savedState"))
            targets.append(paths.home.appendingPathComponent("Library/Containers/\(identifier)"))
            targets.append(paths.home.appendingPathComponent("Library/HTTPStorages/\(identifier)"))
        }
        targets.append(paths.home.appendingPathComponent(
            "Library/Preferences/\(UninstallIdentifiers.uninstaller).plist"))
        targets.append(contentsOf: diagnostics(paths: paths))

        // 目录枚举拿到的路径可能已规范化（/var → /private/var），比较前统一解析，
        // 但对外仍返回调用方给出的写法，避免留下两种拼法。
        let selfPath = selfBundle?.resolvingSymlinksInPath().standardizedFileURL.path
        var kept: [String] = []
        var pending: [String] = []
        var deletable: [String] = []
        for target in targets {
            guard isInstalled(target) else { continue }
            let resolved = target.resolvingSymlinksInPath().standardizedFileURL.path
            if let selfBundle, let selfPath, resolved == selfPath {
                pending.append(selfBundle.path)
            } else {
                deletable.append(target.path)
            }
        }

        if mode == .keepData {
            // 支持目录只删非用户文件；用户文件逐个保留并报告。
            let children = (try? fileManager.contentsOfDirectory(
                at: paths.supportDirectory, includingPropertiesForKeys: nil, options: [])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let rebased = paths.supportDirectory.appendingPathComponent(child.lastPathComponent)
                if UninstallIdentifiers.userFiles.contains(child.lastPathComponent) {
                    kept.append(rebased.path)
                } else {
                    deletable.append(rebased.path)
                }
            }
            deletable.removeAll { kept.contains($0) }
        } else {
            if isInstalled(paths.supportDirectory) { deletable.append(paths.supportDirectory.path) }
        }
        return UninstallPlan(targets: deletable, kept: kept, pendingSelfRemoval: pending,
                             removeSupport: mode == .removeAll)
    }

    /// 执行卸载；`selfBundle` 非空时把它留给 `scheduleSelfRemoval`（自卸载）。
    public static func run(mode: UninstallMode, paths: UninstallPaths, selfBundle: URL? = nil,
                           stopApps: ([String]) -> Void,
                           switchToABCAndDisable: (URL) -> Void) throws -> UninstallOutcome
    {
        let fileManager = FileManager.default
        // 先切回 ABC 并禁用输入源（需要宿主 bundle 里的 helper，必须在删除前做）。
        if fileManager.fileExists(atPath: paths.hostBundle.path) {
            stopApps([UninstallIdentifiers.host])
            switchToABCAndDisable(paths.hostBundle.appendingPathComponent("Contents/Helpers/LampyrisTIS"))
        }
        // 自卸载时不要停自己：只停宿主与安装器，更新程序本体由 detached shell 在退出后删除。
        let stopping = selfBundle == nil
            ? [UninstallIdentifiers.host, UninstallIdentifiers.updater, UninstallIdentifiers.installer]
            : [UninstallIdentifiers.host, UninstallIdentifiers.installer]
        stopApps(stopping)

        let plan = try plan(mode: mode, paths: paths, selfBundle: selfBundle)
        var failures: [String] = []
        var removed = 0
        for path in plan.targets {
            do {
                try fileManager.removeItem(atPath: path)
                removed += 1
            } catch {
                failures.append(path)
            }
        }
        if !failures.isEmpty { throw UninstallError.residual(failures) }

        var leftovers = plan.targets.filter { fileManager.fileExists(atPath: $0) }
        if plan.removeSupport, fileManager.fileExists(atPath: paths.supportDirectory.path) {
            leftovers.append(paths.supportDirectory.path)
        }
        if !leftovers.isEmpty { throw UninstallError.residual(leftovers) }
        return UninstallOutcome(kept: plan.kept, removedCount: removed,
                                pendingSelfRemoval: plan.pendingSelfRemoval)
    }

    /// 诊断日志与崩溃报告（只匹配本产品前缀，不碰其它应用）。
    static func diagnostics(paths: UninstallPaths) -> [URL] {
        let prefixes = ["Lampyris-", "LampyrisUpdateCheck-", "LampyrisInstaller-", "LampyrisUninstaller-"]
        let crashPrefixes = ["Lampyris_", "LampyrisUpdateCheck_", "LampyrisInstaller_", "LampyrisUninstaller_"]
        var found: [URL] = []
        for (directory, names) in [
            (paths.home.appendingPathComponent("Library/Logs/DiagnosticReports"), prefixes),
            (paths.home.appendingPathComponent("Library/Application Support/CrashReporter"), crashPrefixes),
        ] {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for child in children where names.contains(where: { child.lastPathComponent.hasPrefix($0) }) {
                found.append(directory.appendingPathComponent(child.lastPathComponent))
            }
        }
        found.append(URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lampyris-hud-diag.log"))
        return found
    }

    /// 自删除脚本：等本进程退出后再删除这些路径（运行中的 app 不能删自己）。
    /// 只用 `/bin/sh`——系统自带，不引入任何额外依赖；路径单独加引号，不做通配展开。
    public static func selfRemovalScript(pid: Int32, paths: [String]) -> String {
        let quoted = paths.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        return """
        #!/bin/sh
        # 等待调用方退出（最多 10 秒），再删除卸载后仍被占用的本体。
        i=0
        while [ "$i" -lt 50 ]; do
            kill -0 \(pid) 2>/dev/null || break
            sleep 0.2
            i=$((i + 1))
        done
        rm -rf -- \(quoted.joined(separator: " "))
        """
    }

    /// 启动 detached shell 执行自删除；调用方随后应立即退出。
    @discardableResult
    public static func scheduleSelfRemoval(pid: Int32 = ProcessInfo.processInfo.processIdentifier,
                                           paths: [String]) -> Bool {
        guard !paths.isEmpty else { return false }
        let script = selfRemovalScript(pid: pid, paths: paths)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        return true
    }
}
