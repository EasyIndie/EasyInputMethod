import Foundation

/// Where an update may install and keep its private state (ADR-287).
///
/// A normal signed updater always resolves to the production locations. Only a
/// dedicated test build, marked with `LampyrisTestOnly`, may point at an owned
/// private root, and then only for the UUID-bound isolated input method identity.
struct InstallLocation: Sendable {
    let domain: URL
    let support: URL
    let target: InstallTarget
    let isolated: Bool

    static let testBundlePrefix = "cn.jokerhub.Lampyris.WebsiteUpdateCheckTest."
    static let isolatedIdentityPrefix = "cn.jokerhub.inputmethod.LampyrisIMKTest."
    static let rootPrefix = "lampyris-imk-"
    private static let loosePermissions: Int = 0o077

    static func resolve(info: [String: Any],
                        home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        temporary: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        throws -> InstallLocation
    {
        guard info["LampyrisTestOnly"] as? Bool == true else {
            return InstallLocation(domain: home.appendingPathComponent("Library/Input Methods"),
                                   support: home.appendingPathComponent(
                                       "Library/Application Support/Lampyris/updates"),
                                   target: .production, isolated: false)
        }
        guard let bundle = info["CFBundleIdentifier"] as? String,
              let identity = info["LampyrisIsolatedIdentity"] as? String,
              let rootPath = info["LampyrisIsolatedRoot"] as? String,
              !rootPath.isEmpty else {
            throw InstallError.candidateInvalid("测试更新程序缺少隔离绑定")
        }
        let target = try InstallTarget.isolated(identity: identity)
        let uuid = String(identity.dropFirst(isolatedIdentityPrefix.count))
        guard bundle == testBundlePrefix + uuid else {
            throw InstallError.candidateInvalid("测试更新程序标识与隔离身份不符")
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let canonical = try validateRoot(root, uuid: uuid, home: home, temporary: temporary)
        return InstallLocation(domain: canonical.appendingPathComponent("Input Methods"),
                               support: canonical.appendingPathComponent("updates"),
                               target: target, isolated: true)
    }

    /// Rejects anything that is not an owned, owner-marked private root; returns the canonical root.
    @discardableResult
    static func validateRoot(_ root: URL, uuid: String, home: URL, temporary: URL) throws -> URL {
        let manager = FileManager.default
        guard root.path.hasPrefix("/"), root.path == (root.path as NSString).standardizingPath,
              let own = try? manager.attributesOfItem(atPath: root.path),
              own[.type] as? FileAttributeType == .typeDirectory else {
            throw InstallError.candidateInvalid("隔离根路径不符或为符号链接")
        }
        // The root itself may not be a link; ancestor links such as /var -> /private/var are canonicalized.
        let canonical = root.resolvingSymlinksInPath()
        guard canonical.lastPathComponent == rootPrefix + uuid else {
            throw InstallError.candidateInvalid("隔离根身份不符")
        }
        guard allowedParents(home: home, temporary: temporary)
            .contains(canonical.deletingLastPathComponent().path) else {
            throw InstallError.candidateInvalid("隔离根必须在设备私有临时目录或开发根内")
        }
        guard let attributes = try? manager.attributesOfItem(atPath: canonical.path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.uint32Value == geteuid(),
              let mode = attributes[.posixPermissions] as? NSNumber,
              mode.intValue & loosePermissions == 0 else {
            throw InstallError.candidateInvalid("隔离根归属或权限不符")
        }
        let marker = canonical.appendingPathComponent("owner")
        guard let markerAttributes = try? manager.attributesOfItem(atPath: marker.path),
              markerAttributes[.type] as? FileAttributeType == .typeRegular,
              let markerOwner = markerAttributes[.ownerAccountID] as? NSNumber,
              markerOwner.uint32Value == geteuid(),
              let markerMode = markerAttributes[.posixPermissions] as? NSNumber,
              markerMode.intValue & loosePermissions == 0,
              let content = try? String(contentsOf: marker, encoding: .utf8),
              content == canonical.lastPathComponent else {
            throw InstallError.candidateInvalid("隔离根所有权标记不符")
        }
        return canonical
    }

    private static func allowedParents(home: URL, temporary: URL) -> Set<String> {
        var parents: Set<String> = ["/private/tmp", "/tmp", "/private/var/tmp", "/var/tmp"]
        parents.insert(home.appendingPathComponent("Library/Application Support/LampyrisIMKDev").path)
        // APFS firmlinks may keep /var spelled as /var, so accept both spellings of the private T dir.
        for candidate in [temporary, temporary.resolvingSymlinksInPath()] {
            let path = candidate.path
            guard candidate.lastPathComponent == "T",
                  path.hasPrefix("/private/var/folders/") || path.hasPrefix("/var/folders/") else {
                continue
            }
            parents.insert(path)
        }
        return parents
    }
}
