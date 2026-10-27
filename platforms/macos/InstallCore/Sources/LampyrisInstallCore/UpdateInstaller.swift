import CryptoKit
import Foundation

/// 升级安装的失败原因；任何失败都应保持/恢复到升级前状态。
public enum InstallError: LocalizedError, Equatable {
    case payloadMissing(String)
    case payloadEmpty
    case domainMissing(String)
    case missingBundle
    case ambiguousBundle
    case symlinkRejected
    case candidateInvalid(String)
    case hostStopFailed(String)
    case replaceFailed(String)
    case receiptFailed(String)

    public var errorDescription: String? {
        switch self {
        case .payloadMissing(let detail): return "负载不可用：" + detail
        case .payloadEmpty: return "负载为空"
        case .domainMissing(let path): return "安装目标目录不存在：" + path
        case .missingBundle: return "负载中缺少 Lampyris.app"
        case .ambiguousBundle: return "负载中有多个候选 Lampyris.app"
        case .symlinkRejected: return "安装位置是符号链接，拒绝替换"
        case .candidateInvalid(let detail): return "候选校验失败：" + detail
        case .hostStopFailed(let detail): return "停止宿主失败：" + detail
        case .replaceFailed(let detail): return "替换失败：" + detail
        case .receiptFailed(let detail): return "写入升级记录失败：" + detail
        }
    }
}

/// 可注入的外部动作（测试用桩替换）。
public struct InstallEnvironment: Sendable {
    public var validateCandidate: @Sendable (URL) throws -> Void
    public var stopHost: @Sendable (URL) throws -> Void

    public init(validateCandidate: @escaping @Sendable (URL) throws -> Void,
                stopHost: @escaping @Sendable (URL) throws -> Void) {
        self.validateCandidate = validateCandidate
        self.stopHost = stopHost
    }
}

public struct InstallReceipt: Sendable, Equatable {
    public let payloadSHA256: String
    public let signature: String
    public let installed: String
    public let previous: String?
    public let candidateExecutableSHA256: String
    public let installedExecutableSHA256: String
    public let dryRun: Bool
    /// 更新程序自身的落地路径（ADR-295）；未带自更新或失败时为 nil。
    public let updaterBundle: String?
}

/// Candidate identity and executable are bound together for every install operation.
public struct InstallTarget: Sendable {
    public let bundleName: String
    public let executablePath: String
    public let identity: String

    public static let production = InstallTarget(
        bundleName: "Lampyris.app", executablePath: "Contents/MacOS/Lampyris",
        identity: "cn.jokerhub.inputmethod.Lampyris")

    /// Only the UUID-bound IMK test identity may use the isolated target shape.
    public static func isolated(identity: String) throws -> InstallTarget {
        let prefix = "cn.jokerhub.inputmethod.LampyrisIMKTest."
        guard identity.hasPrefix(prefix),
              let uuid = UUID(uuidString: String(identity.dropFirst(prefix.count))),
              identity == prefix + uuid.uuidString.lowercased() else {
            throw InstallError.candidateInvalid("隔离输入法标识不符")
        }
        return InstallTarget(bundleName: "LampyrisIMKTest.app",
                             executablePath: "Contents/MacOS/LampyrisIMKTest", identity: identity)
    }

    /// 更新程序自身的目标（ADR-295）：装到 `~/Applications`，与输入法用同一套替换/回滚实现。
    public static let updater = InstallTarget(
        bundleName: "LampyrisUpdateCheck.app", executablePath: "Contents/MacOS/LampyrisUpdateCheck",
        identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck")

    private init(bundleName: String, executablePath: String, identity: String) {
        self.bundleName = bundleName
        self.executablePath = executablePath
        self.identity = identity
    }
}

/// 已验签的原地升级（Swift 版，与 packaging/macos/upgrade.py 语义一致）。
public enum UpdateInstaller {
    public static let bundleName = InstallTarget.production.bundleName
    public static let executablePath = InstallTarget.production.executablePath
    public static let identity = InstallTarget.production.identity

    public static func install(payload: URL, signature: String, publicKeyBase64: String,
                               domain: URL, support: URL,
                               environment: InstallEnvironment,
                               target: InstallTarget = .production,
                               dryRun: Bool = false,
                               selfUpdate: SelfUpdate? = nil) throws -> InstallReceipt {
        guard FileManager.default.fileExists(atPath: payload.path) else {
            throw InstallError.payloadMissing("负载不存在：\(payload.path)")
        }
        guard let size = try? payload.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw InstallError.payloadEmpty
        }
        let verifier = try PayloadVerifier(publicKeyBase64: publicKeyBase64)
        guard try verifier.verify(fileAt: payload, signatureBase64: signature) else {
            throw InstallError.candidateInvalid("负载签名无效")
        }
        // The updater runs on an installed system, so the target directory must already exist;
        // refusing here keeps a broken install from being masked (ADR-289).
        guard isDirectory(domain) else { throw InstallError.domainMissing(domain.path) }
        let destination = domain.appendingPathComponent(target.bundleName)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let work = support.appendingPathComponent("upgrade-\(stamp)-\(UUID().uuidString.prefix(8))")
        let staging = work.appendingPathComponent("staging")
        // Only a successful upgrade keeps work/backup; all preflight and rolled-back failures clean it.
        var keepBackup = false
        defer { if !keepBackup { try? FileManager.default.removeItem(at: work) } }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let candidate = try extract(payload: payload, staging: staging, bundleName: target.bundleName)
        try environment.validateCandidate(candidate)
        let candidateExec = candidate.appendingPathComponent(target.executablePath)
        var receiptBase = InstallReceipt(
            payloadSHA256: try sha256(payload), signature: signature,
            installed: destination.path, previous: nil,
            candidateExecutableSHA256: try sha256(candidateExec),
            installedExecutableSHA256: "", dryRun: dryRun, updaterBundle: nil)
        if dryRun { return receiptBase }
        let previous: String?
        do {
            previous = try replaceBundle(candidate: candidate, destination: destination,
                                         backupRoot: work.appendingPathComponent("backup"),
                                         environment: environment, target: target)
        } catch {
            // Keep the backup when rollback itself failed: manual recovery needs those bytes.
            if case InstallError.replaceFailed = error { keepBackup = true }
            throw error
        }
        let installedExec = destination.appendingPathComponent(target.executablePath)
        // 输入法已落地；自更新是次要步骤，失败不能把输入法回滚（ADR-295）。
        let selfUpdated = selfUpdate.flatMap { update -> SelfUpdateOutcome? in
            try? installSelfUpdate(update, payloadStaging: candidate.deletingLastPathComponent())
        }
        let receipt = InstallReceipt(
            payloadSHA256: receiptBase.payloadSHA256, signature: signature,
            installed: destination.path, previous: previous,
            candidateExecutableSHA256: receiptBase.candidateExecutableSHA256,
            installedExecutableSHA256: try sha256(installedExec), dryRun: false,
            updaterBundle: selfUpdated?.installed)
        do {
            try writeReceipt(receipt, support: support)
        } catch {
            // 记账失败视为整体失败：输入法与自更新都回到升级前，避免「装上新版却没记录」或
            // 「更新程序已是新版、输入法还是旧版」这种让用户卡住的状态。
            do {
                try revertBundle(destination: destination, previous: previous)
                if let selfUpdated {
                    try revertBundle(destination: URL(fileURLWithPath: selfUpdated.installed),
                                     previous: selfUpdated.previous)
                }
            } catch {
                keepBackup = true
                throw InstallError.replaceFailed(
                    "回执写入失败且回滚失败，备份位于 \(work.path)：\(error.localizedDescription)")
            }
            throw error
        }
        try? FileManager.default.removeItem(at: staging)
        keepBackup = previous != nil
        return receipt
    }

    /// 更新程序自更新（ADR-295）：只替换 `~/Applications` 里的程序本体，运行中的实例保持不动，
    /// 下次启动生效；候选缺失/校验失败/替换失败都不影响已经完成的输入法升级。
    /// 自更新结果：落地路径与（可能为空的）旧版备份，便于上层失败时整笔回滚。
    public struct SelfUpdateOutcome: Sendable, Equatable {
        public let installed: String
        public let previous: String?
    }

    public struct SelfUpdate: Sendable {
        public let directory: URL
        public let environment: InstallEnvironment
        public init(directory: URL, environment: InstallEnvironment) {
            self.directory = directory
            self.environment = environment
        }
    }

    /// 安装负载里自带的更新程序本体（缺省时返回 nil，不算失败）。
    public static func installSelfUpdate(_ update: SelfUpdate, payloadStaging: URL) throws
        -> SelfUpdateOutcome?
    {
        let candidate = payloadStaging.appendingPathComponent(InstallTarget.updater.bundleName)
        guard isDirectory(candidate), !isSymlink(candidate) else { return nil }
        let destination = update.directory.appendingPathComponent(InstallTarget.updater.bundleName)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupRoot = update.directory.appendingPathComponent(".lampyris-updater-backup-\(stamp)")
        let previous = try replaceBundle(candidate: candidate, destination: destination,
                                         backupRoot: backupRoot, environment: update.environment,
                                         target: .updater)
        return SelfUpdateOutcome(installed: destination.path, previous: previous)
    }

    /// 把一次替换恢复原状：有备份就换回，没有就删掉刚装上的那份。
    static func revertBundle(destination: URL, previous: String?) throws {
        try? FileManager.default.removeItem(at: destination)
        guard let previous else { return }
        guard FileManager.default.fileExists(atPath: previous) else {
            throw InstallError.replaceFailed("备份不存在：\(previous)")
        }
        try FileManager.default.moveItem(atPath: previous, toPath: destination.path)
    }

    /// 原地替换的单一实现（DMG 安装器、升级流程、自更新共用，ADR-295）。
    /// 先把候选拷到目标卷内的隐藏 staging（来源可能是只读 DMG），再备份旧包、移动到位、落地复验，
    /// 任一步失败都恢复到替换前状态。
    @discardableResult
    public static func replaceBundle(candidate: URL, destination: URL, backupRoot: URL,
                                     environment: InstallEnvironment,
                                     target: InstallTarget = .production) throws -> String? {
        guard isDirectory(candidate), !isSymlink(candidate) else {
            throw InstallError.missingBundle
        }
        let domain = destination.deletingLastPathComponent()
        guard isDirectory(domain) else { throw InstallError.domainMissing(domain.path) }
        if isSymlink(destination) { throw InstallError.symlinkRejected }
        let staging = domain.appendingPathComponent(".lampyris-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(target.bundleName)
        try FileManager.default.copyItem(at: candidate, to: staged)
        try environment.validateCandidate(staged)
        var previous: URL?
        var placed = false
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try environment.stopHost(destination.appendingPathComponent(target.executablePath))
                try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let backup = backupRoot.appendingPathComponent(target.bundleName)
                try? FileManager.default.removeItem(at: backup)
                try FileManager.default.moveItem(at: destination, to: backup)
                previous = backup
            }
            try FileManager.default.moveItem(at: staged, to: destination)
            placed = true
            try environment.validateCandidate(destination)
            return previous?.path
        } catch {
            do {
                try rollback(destination: destination, previous: previous, placed: placed)
            } catch {
                throw InstallError.replaceFailed("自动回滚失败，备份位于 \(backupRoot.path)：\(error.localizedDescription)")
            }
            throw error
        }
    }

    static func extract(payload: URL, staging: URL, bundleName: String = UpdateInstaller.bundleName) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", payload.path, staging.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw InstallError.missingBundle }
        let direct = staging.appendingPathComponent(bundleName)
        if isDirectory(direct) { return direct }
        let children = (try? FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)) ?? []
        let wrapped = children.filter { isDirectory($0.appendingPathComponent(bundleName)) }
        guard wrapped.count == 1 else {
            throw wrapped.isEmpty ? InstallError.missingBundle : InstallError.ambiguousBundle
        }
        return wrapped[0].appendingPathComponent(bundleName)
    }

    static func rollback(destination: URL, previous: URL?, placed: Bool) throws {
        if placed { try FileManager.default.removeItem(at: destination) }
        if let previous {
            try FileManager.default.moveItem(at: previous, to: destination)
        }
    }

    static func writeReceipt(_ receipt: InstallReceipt, support: URL) throws {
        let folder = support.appendingPathComponent("receipts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let name = "\(ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")).json"
        let data = try JSONEncoder().encode(ReceiptPayload(receipt: receipt))
        let url = folder.appendingPathComponent(name)
        try data.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private struct ReceiptPayload: Encodable {
        let payloadSHA256: String
        let signature: String
        let installed: String
        let previous: String?
        let candidateExecutableSHA256: String
        let installedExecutableSHA256: String
        init(receipt: InstallReceipt) {
            payloadSHA256 = receipt.payloadSHA256
            signature = receipt.signature
            installed = receipt.installed
            previous = receipt.previous
            candidateExecutableSHA256 = receipt.candidateExecutableSHA256
            installedExecutableSHA256 = receipt.installedExecutableSHA256
        }
    }

    public static func sha256(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw InstallError.payloadMissing("无法读取：\(url.path)")
        }
        return PayloadVerifier.sha256Hex(data)
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}

extension PayloadVerifier {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
