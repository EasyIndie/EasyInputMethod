import Foundation
import XCTest

@testable import WebsiteUpdateCheck

final class InstallLocationTests: XCTestCase {
    private var created: [URL] = []

    override func tearDownWithError() throws {
        for url in created { try? FileManager.default.removeItem(at: url) }
        created = []
    }

    private func makeRoot(uuid: UUID = UUID(), in parent: URL? = nil, mode: Int = 0o700,
                          markerContent: String? = nil, symlink: Bool = false) throws -> URL {
        let base = parent ?? FileManager.default.temporaryDirectory
        let root = base.appendingPathComponent("lampyris-imk-\(uuid.uuidString.lowercased())")
        if symlink {
            let real = base.appendingPathComponent("real-\(uuid.uuidString.lowercased())")
            try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
            created.append(real)
            try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: real.path)
            let marker = real.appendingPathComponent("owner")
            try root.lastPathComponent.write(to: marker, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
            try FileManager.default.createSymbolicLink(at: root, withDestinationURL: real)
            created.append(root)
            return root
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        created.append(root)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: root.path)
        let marker = root.appendingPathComponent("owner")
        try (markerContent ?? root.lastPathComponent).write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        return root
    }

    private func isolatedInfo(root: URL, uuid: UUID,
                              bundle: String? = nil,
                              identity: String? = nil) -> [String: Any] {
        let suffix = uuid.uuidString.lowercased()
        return ["CFBundleIdentifier": bundle ?? InstallLocation.testBundlePrefix + suffix,
                "LampyrisTestOnly": true,
                "LampyrisIsolatedIdentity":
                    identity ?? InstallLocation.isolatedIdentityPrefix + suffix,
                "LampyrisIsolatedRoot": root.path]
    }

    func testNormalBuildAlwaysResolvesToProduction() throws {
        let root = try makeRoot()
        let info: [String: Any] = ["CFBundleIdentifier": "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                                   "LampyrisIsolatedRoot": root.path]
        let location = try InstallLocation.resolve(info: info)
        XCTAssertFalse(location.isolated)
        XCTAssertEqual(location.target.identity, "cn.jokerhub.inputmethod.Lampyris")
        XCTAssertEqual(location.domain.lastPathComponent, "Input Methods")
        XCTAssertTrue(location.domain.path.contains("/Library/Input Methods"))
        XCTAssertTrue(location.support.path.hasSuffix("/Library/Application Support/Lampyris/updates"))
        XCTAssertFalse(location.domain.path.hasPrefix(root.path))
    }

    func testOwnedTemporaryRootResolvesToIsolatedTarget() throws {
        let uuid = UUID()
        let root = try makeRoot(uuid: uuid)
        let location = try InstallLocation.resolve(info: isolatedInfo(root: root, uuid: uuid))
        XCTAssertTrue(location.isolated)
        XCTAssertEqual(location.domain, root.resolvingSymlinksInPath().appendingPathComponent("Input Methods"))
        XCTAssertEqual(location.support, root.resolvingSymlinksInPath().appendingPathComponent("updates"))
        XCTAssertEqual(location.target.bundleName, "LampyrisIMKTest.app")
        XCTAssertEqual(location.target.executablePath, "Contents/MacOS/LampyrisIMKTest")
        XCTAssertTrue(location.target.identity.hasSuffix(uuid.uuidString.lowercased()))
    }

    func testDevelopmentRootUnderPrivateDevDirectoryIsAccepted() throws {
        let uuid = UUID()
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-home-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        created.append(home)
        let development = home.appendingPathComponent("Library/Application Support/LampyrisIMKDev")
        try FileManager.default.createDirectory(at: development, withIntermediateDirectories: true)
        let root = try makeRoot(uuid: uuid, in: development)
        let location = try InstallLocation.resolve(info: isolatedInfo(root: root, uuid: uuid), home: home)
        XCTAssertTrue(location.isolated)
        XCTAssertEqual(location.domain,
                       root.resolvingSymlinksInPath().appendingPathComponent("Input Methods"))
    }

    func testMissingBindingOrMismatchedIdentityIsRejected() throws {
        let uuid = UUID()
        let root = try makeRoot(uuid: uuid)
        var info = isolatedInfo(root: root, uuid: uuid)
        info.removeValue(forKey: "LampyrisIsolatedRoot")
        XCTAssertThrowsError(try InstallLocation.resolve(info: info))

        let other = UUID()
        XCTAssertThrowsError(try InstallLocation.resolve(
            info: isolatedInfo(root: root, uuid: uuid, bundle: InstallLocation.testBundlePrefix
                + other.uuidString.lowercased())))
        XCTAssertThrowsError(try InstallLocation.resolve(
            info: isolatedInfo(root: root, uuid: uuid, identity:
                InstallLocation.isolatedIdentityPrefix + other.uuidString.lowercased())))
        XCTAssertThrowsError(try InstallLocation.resolve(
            info: isolatedInfo(root: root, uuid: uuid, identity: "cn.jokerhub.inputmethod.Lampyris")))
        XCTAssertThrowsError(try InstallLocation.resolve(
            info: isolatedInfo(root: root, uuid: uuid, bundle: "cn.jokerhub.Lampyris.WebsiteUpdateCheck")))
    }

    func testRootMustBeOwnedSymlinkFreeAndOwnerMarked() throws {
        let symlinkUUID = UUID()
        let symlink = try makeRoot(uuid: symlinkUUID, symlink: true)
        XCTAssertThrowsError(try InstallLocation.resolve(info: isolatedInfo(root: symlink, uuid: symlinkUUID)))

        let looseUUID = UUID()
        let loose = try makeRoot(uuid: looseUUID, mode: 0o755)
        XCTAssertThrowsError(try InstallLocation.resolve(info: isolatedInfo(root: loose, uuid: looseUUID)))

        let mismatchUUID = UUID()
        let mismatch = try makeRoot(uuid: mismatchUUID, markerContent: "someone-else")
        XCTAssertThrowsError(try InstallLocation.resolve(info: isolatedInfo(root: mismatch, uuid: mismatchUUID)))

        let outsideUUID = UUID()
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-outside-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        created.append(outside)
        let nested = try makeRoot(uuid: outsideUUID, in: outside)
        XCTAssertThrowsError(try InstallLocation.resolve(info: isolatedInfo(root: nested, uuid: outsideUUID)))

        let missingUUID = UUID()
        let missingMarker = try makeRoot(uuid: missingUUID)
        try FileManager.default.removeItem(at: missingMarker.appendingPathComponent("owner"))
        XCTAssertThrowsError(try InstallLocation.resolve(info: isolatedInfo(root: missingMarker, uuid: missingUUID)))
    }
}
