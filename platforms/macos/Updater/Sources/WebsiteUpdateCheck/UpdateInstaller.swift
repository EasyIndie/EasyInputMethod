import CryptoKit
import Foundation

/// 升级安装的失败原因；任何失败都应保持/恢复到升级前状态。
public enum InstallError: Error, Equatable {
    case payloadMissing
    case payloadEmpty
    case missingBundle
    case ambiguousBundle
    case symlinkRejected
    case candidateInvalid(String)
    case hostStopFailed(String)
    case replaceFailed(String)
    case receiptFailed(String)
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
}

/// 已验签的原地升级（Swift 版，与 packaging/macos/upgrade.py 语义一致）。
public enum UpdateInstaller {
    public static let bundleName = "Lampyris.app"
    public static let executablePath = "Contents/MacOS/Lampyris"
    public static let identity = "cn.jokerhub.inputmethod.Lampyris"

    public static func install(payload: URL, signature: String, publicKeyBase64: String,
                               domain: URL, support: URL,
                               environment: InstallEnvironment,
                               dryRun: Bool = false) throws -> InstallReceipt {
        guard FileManager.default.fileExists(atPath: payload.path) else {
            throw InstallError.payloadMissing
        }
        guard let size = try? payload.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0 else {
            throw InstallError.payloadEmpty
        }
        let verifier = try PayloadVerifier(publicKeyBase64: publicKeyBase64)
        guard try verifier.verify(fileAt: payload, signatureBase64: signature) else {
            throw InstallError.candidateInvalid("负载签名无效")
        }
        let destination = domain.appendingPathComponent(bundleName)
        if isSymlink(destination) { throw InstallError.symlinkRejected }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let work = support.appendingPathComponent("upgrade-\(stamp)-\(UUID().uuidString.prefix(8))")
        let staging = work.appendingPathComponent("staging")
        let backupDir = work.appendingPathComponent("backup")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let candidate = try extract(payload: payload, staging: staging)
        try environment.validateCandidate(candidate)
        let candidateExec = candidate.appendingPathComponent(executablePath)
        let receiptBase = InstallReceipt(
            payloadSHA256: try sha256(payload), signature: signature,
            installed: destination.path, previous: nil,
            candidateExecutableSHA256: try sha256(candidateExec),
            installedExecutableSHA256: "", dryRun: dryRun)
        if dryRun {
            try? FileManager.default.removeItem(at: work)
            return receiptBase
        }
        var previous: URL?
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try environment.stopHost(destination.appendingPathComponent(executablePath))
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: false,
                                                        attributes: [.posixPermissions: 0o700])
                previous = backupDir.appendingPathComponent(bundleName)
                try FileManager.default.moveItem(at: destination, to: previous!)
            }
            do {
                try FileManager.default.moveItem(at: candidate, to: destination)
            } catch {
                if let previous, !FileManager.default.fileExists(atPath: destination.path) {
                    try? FileManager.default.moveItem(at: previous, to: destination)
                }
                throw InstallError.replaceFailed(error.localizedDescription)
            }
            do {
                try environment.validateCandidate(destination)
            } catch {
                rollback(destination: destination, previous: previous, work: work)
                throw InstallError.candidateInvalid("落地复验失败：\(error.localizedDescription)")
            }
            let installedExec = destination.appendingPathComponent(executablePath)
            let receipt = InstallReceipt(
                payloadSHA256: receiptBase.payloadSHA256, signature: signature,
                installed: destination.path, previous: previous?.path,
                candidateExecutableSHA256: receiptBase.candidateExecutableSHA256,
                installedExecutableSHA256: try sha256(installedExec), dryRun: false)
            try writeReceipt(receipt, support: support)
            try? FileManager.default.removeItem(at: staging)
            return receipt
        } catch let error as InstallError {
            throw error
        } catch {
            rollback(destination: destination, previous: previous, work: work)
            throw InstallError.replaceFailed(error.localizedDescription)
        }
    }

    static func extract(payload: URL, staging: URL) throws -> URL {
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

    static func rollback(destination: URL, previous: URL?, work: URL) {
        guard let previous, FileManager.default.fileExists(atPath: previous.path) else { return }
        let rejected = work.appendingPathComponent("rejected.app")
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.moveItem(at: destination, to: rejected)
        }
        if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.moveItem(at: previous, to: destination)
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

    static func sha256(_ url: URL) throws -> String {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw InstallError.payloadMissing
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
