import CryptoKit
import Foundation
import XCTest

@testable import WebsiteUpdateCheck

final class DownloadPolicyTests: XCTestCase {
    func testOnlyHttpsPayloadsAreAllowed() {
        XCTAssertTrue(UpdateDownloader.secure(URL(string: "https://example.com/a.zip")!))
        XCTAssertFalse(UpdateDownloader.secure(URL(string: "http://example.com/a.zip")!))
        XCTAssertFalse(UpdateDownloader.secure(URL(string: "file:///tmp/a.zip")!))
        XCTAssertFalse(UpdateDownloader.secure(URL(string: "https://u:p@example.com/a.zip")!))
    }

    func testDownloadedPayloadRemovesPrivateDirectoryWhenReleased() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-download-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = folder.appendingPathComponent("payload.zip")
        try Data("payload".utf8).write(to: file)
        var payload: DownloadedPayload? = DownloadedPayload(url: file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        payload = nil
        XCTAssertNil(payload)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func testRedirectPolicyAllowsMirrorsAndGithubAssets() {
        let origin = URL(string: "https://cn.example.com/a.zip")!
        XCTAssertTrue(UpdateDownloader.allowsRedirect(from: origin, to: URL(string: "https://cn.example.com/b.zip")!))
        XCTAssertTrue(UpdateDownloader.allowsRedirect(
            from: origin, to: URL(string: "https://release-assets.githubusercontent.com/x")!))
        XCTAssertFalse(UpdateDownloader.allowsRedirect(from: origin, to: URL(string: "https://evil.example/x")!))
        XCTAssertFalse(UpdateDownloader.allowsRedirect(from: origin, to: URL(string: "http://cn.example.com/x")!))
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    private var count = 0

    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
}

final class UpdateInstallerTests: XCTestCase {
    private var folder: URL!
    private var domain: URL!
    private var support: URL!
    private var key: Curve25519.Signing.PrivateKey!
    private var publicKey: String!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        domain = folder.appendingPathComponent("Input Methods")
        support = folder.appendingPathComponent("Support")
        try FileManager.default.createDirectory(at: domain, withIntermediateDirectories: true)
        key = Curve25519.Signing.PrivateKey()
        publicKey = key.publicKey.rawRepresentation.base64EncodedString()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeApp(_ parent: URL, marker: String,
                         target: InstallTarget = .production) throws -> URL {
        let app = parent.appendingPathComponent(target.bundleName)
        let executable = app.appendingPathComponent(target.executablePath)
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try marker.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return app
    }

    private func makePayload(_ parent: URL, wrapped: Bool = false,
                             target: InstallTarget = .production) throws -> URL {
        let build = folder.appendingPathComponent("build-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        let app: URL
        if wrapped {
            let wrapper = build.appendingPathComponent("Lampyris-0.0.1-universal")
            try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
            app = try makeApp(wrapper, marker: "new", target: target)
            try "notes".write(to: wrapper.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        } else {
            app = try makeApp(build, marker: "new", target: target)
        }
        let zip = folder.appendingPathComponent("payload-\(UUID().uuidString).zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return zip
    }

    private func signature(_ payload: URL) throws -> String {
        let data = try Data(contentsOf: payload)
        return try key.signature(for: data).base64EncodedString()
    }

    private func environment(validate: @escaping @Sendable (URL) throws -> Void = { _ in },
                             stop: @escaping @Sendable (URL) throws -> Void = { _ in }) -> InstallEnvironment {
        InstallEnvironment(validateCandidate: validate, stopHost: stop)
    }

    func testIsolatedTargetRejectsProductionAndInvalidUUID() {
        for identity in ["cn.jokerhub.inputmethod.Lampyris",
                         "cn.jokerhub.inputmethod.LampyrisIMKTest.not-a-uuid",
                         "cn.jokerhub.inputmethod.LampyrisIMKTest.00000000-0000-0000-0000-000000000000.extra"] {
            XCTAssertThrowsError(try InstallTarget.isolated(identity: identity))
        }
        XCTAssertEqual(InstallTarget.production.bundleName, "Lampyris.app")
        XCTAssertEqual(InstallTarget.production.executablePath, "Contents/MacOS/Lampyris")
        XCTAssertEqual(InstallTarget.production.identity, "cn.jokerhub.inputmethod.Lampyris")
    }

    func testIsolatedEnvironmentRejectsExecutableMismatchBeforeSigningCheck() throws {
        let target = try InstallTarget.isolated(identity:
            "cn.jokerhub.inputmethod.LampyrisIMKTest.00000000-0000-0000-0000-000000000004")
        let app = try makeApp(folder, marker: "isolated", target: target)
        let info = ["CFBundleIdentifier": target.identity, "CFBundleExecutable": "Lampyris"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        XCTAssertThrowsError(try DefaultInstallEnvironment.make(target: target).validateCandidate(app)) { error in
            guard case InstallError.candidateInvalid(let reason) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertTrue(reason.contains("可执行文件身份不符"))
        }
    }

    func testIsolatedTargetInstallsAndBacksUpOnlyTestBundle() throws {
        let target = try InstallTarget.isolated(identity:
            "cn.jokerhub.inputmethod.LampyrisIMKTest.00000000-0000-0000-0000-000000000001")
        let production = try makeApp(domain, marker: "production")
        let original = try makeApp(domain, marker: "old", target: target)
        let payload = try makePayload(folder, target: target)
        let stopped = Flag()
        let receipt = try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(stop: { executable in
                XCTAssertTrue(executable.path.hasSuffix("/LampyrisIMKTest.app/Contents/MacOS/LampyrisIMKTest"))
                stopped.set()
            }), target: target)
        XCTAssertTrue(stopped.isSet)
        XCTAssertEqual(receipt.installed, original.path)
        XCTAssertEqual(try String(contentsOf: original.appendingPathComponent(target.executablePath),
                                  encoding: .utf8), "new")
        let previous = try XCTUnwrap(receipt.previous)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: previous)
            .appendingPathComponent(target.executablePath), encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: production.appendingPathComponent(UpdateInstaller.executablePath),
                                  encoding: .utf8), "production")
    }

    func testIsolatedTargetRejectsProductionBundleWithoutTouchingEitherInstall() throws {
        let target = try InstallTarget.isolated(identity:
            "cn.jokerhub.inputmethod.LampyrisIMKTest.00000000-0000-0000-0000-000000000002")
        let production = try makeApp(domain, marker: "production")
        let isolated = try makeApp(domain, marker: "isolated", target: target)
        let payload = try makePayload(folder)
        let stopped = Flag()
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(stop: { _ in stopped.set() }), target: target))
        XCTAssertFalse(stopped.isSet)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: support.path), [])
        XCTAssertEqual(try String(contentsOf: production.appendingPathComponent(UpdateInstaller.executablePath),
                                  encoding: .utf8), "production")
        XCTAssertEqual(try String(contentsOf: isolated.appendingPathComponent(target.executablePath),
                                  encoding: .utf8), "isolated")
    }

    func testIsolatedTargetPostValidationFailureRestoresTestBundle() throws {
        let target = try InstallTarget.isolated(identity:
            "cn.jokerhub.inputmethod.LampyrisIMKTest.00000000-0000-0000-0000-000000000003")
        let production = try makeApp(domain, marker: "production")
        let isolated = try makeApp(domain, marker: "old", target: target)
        let payload = try makePayload(folder, target: target)
        let calls = Flag()
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(validate: { _ in
                if calls.increment() >= 2 { throw InstallError.candidateInvalid("post") }
            }), target: target))
        XCTAssertEqual(try String(contentsOf: isolated.appendingPathComponent(target.executablePath),
                                  encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: production.appendingPathComponent(UpdateInstaller.executablePath),
                                  encoding: .utf8), "production")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: support.path), [])
    }

    func testMissingTargetDirectoryIsRejectedBeforeStoppingHost() throws {
        let missing = folder.appendingPathComponent("No Input Methods")
        let payload = try makePayload(folder)
        let stopped = Flag()
        let env = environment(stop: { _ in stopped.set() })
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: missing, support: support, environment: env)) { error in
            guard case InstallError.domainMissing(let path) = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(path, missing.path)
        }
        XCTAssertFalse(stopped.isSet)
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.path))
    }

    func testFreshInstallPlacesBundleAndWritesReceipt() throws {
        let payload = try makePayload(folder)
        let receipt = try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: environment())
        let installed = domain.appendingPathComponent(UpdateInstaller.bundleName)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "new")
        XCTAssertNil(receipt.previous)
        XCTAssertFalse(receipt.dryRun)
        let receipts = try FileManager.default.contentsOfDirectory(at: support.appendingPathComponent("receipts"),
                                                                  includingPropertiesForKeys: nil)
        XCTAssertEqual(receipts.count, 1)
        let mode = try FileManager.default.attributesOfItem(atPath: receipts[0].path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o600)
    }

    func testUpgradeKeepsBackupAndStopsHost() throws {
        _ = try makeApp(domain, marker: "old")
        let payload = try makePayload(folder, wrapped: true)
        let stopped = Flag()
        let receipt = try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(stop: { executable in
                XCTAssertTrue(executable.path.hasSuffix(UpdateInstaller.executablePath))
                stopped.set()
            }))
        XCTAssertTrue(stopped.isSet)
        let installed = domain.appendingPathComponent(UpdateInstaller.bundleName)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "new")
        let previous = try XCTUnwrap(receipt.previous)
        XCTAssertEqual(try String(contentsOf: URL(fileURLWithPath: previous)
            .appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "old")
    }

    func testRollbackRestoresOldBundleWhenPostValidationFails() throws {
        _ = try makeApp(domain, marker: "old")
        let payload = try makePayload(folder)
        let calls = Flag()
        let env = environment(validate: { _ in
            if calls.increment() >= 2 { throw InstallError.candidateInvalid("post") }
        })
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: env))
        let installed = domain.appendingPathComponent(UpdateInstaller.bundleName)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "old")
    }

    func testFreshInstallPostValidationFailureRemovesNewBundle() throws {
        let payload = try makePayload(folder)
        let calls = Flag()
        let env = environment(validate: { _ in
            if calls.increment() >= 2 { throw InstallError.candidateInvalid("post") }
        })
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: env))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: domain.appendingPathComponent(UpdateInstaller.bundleName).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: support.path), [])
    }

    func testFreshInstallReceiptFailureRemovesNewBundle() throws {
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: support.appendingPathComponent("receipts"))
        let payload = try makePayload(folder)
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: environment()))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: domain.appendingPathComponent(UpdateInstaller.bundleName).path))
    }

    func testPreflightFailureCleansStaging() throws {
        let payload = try makePayload(folder)
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(validate: { _ in throw InstallError.candidateInvalid("pre") })))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: support.path), [])
    }

    func testInvalidArchiveCleansStagingWithoutStoppingHost() throws {
        let payload = folder.appendingPathComponent("invalid.zip")
        try Data("not a zip".utf8).write(to: payload)
        let stopped = Flag()
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(stop: { _ in stopped.set() })))
        XCTAssertFalse(stopped.isSet)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: support.path), [])
    }

    func testRejectsBadSignatureAndLeavesInstallUntouched() throws {
        _ = try makeApp(domain, marker: "old")
        let payload = try makePayload(folder)
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: Data(repeating: 0, count: 64).base64EncodedString(),
            publicKeyBase64: publicKey, domain: domain, support: support, environment: environment()))
        let installed = domain.appendingPathComponent(UpdateInstaller.bundleName)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "old")
    }

    func testDryRunDoesNotStopOrReplace() throws {
        _ = try makeApp(domain, marker: "old")
        let payload = try makePayload(folder)
        let stopped = Flag()
        let receipt = try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support,
            environment: environment(stop: { _ in stopped.set() }), dryRun: true)
        XCTAssertTrue(receipt.dryRun)
        XCTAssertFalse(stopped.isSet)
        let installed = domain.appendingPathComponent(UpdateInstaller.bundleName)
        XCTAssertEqual(try String(contentsOf: installed.appendingPathComponent(UpdateInstaller.executablePath), encoding: .utf8), "old")
    }

    func testRejectsAmbiguousWrapperAndSymlinkDestination() throws {
        let merge = folder.appendingPathComponent("merge")
        for name in ["one", "two"] {
            let wrapper = merge.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: wrapper, withIntermediateDirectories: true)
            _ = try makeApp(wrapper.appendingPathComponent("x"), marker: name)
        }
        let ambiguous = folder.appendingPathComponent("ambiguous.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", merge.path, ambiguous.path]
        try process.run()
        process.waitUntilExit()
        // 顶层是 merge/ 而非 Lampyris.app，且没有唯一的下一层 bundle：拒绝。
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: ambiguous, signature: try signature(ambiguous), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: environment()))

        let real = try makeApp(folder.appendingPathComponent("real"), marker: "linked")
        try FileManager.default.createSymbolicLink(
            at: domain.appendingPathComponent(UpdateInstaller.bundleName), withDestinationURL: real)
        let payload = try makePayload(folder)
        XCTAssertThrowsError(try UpdateInstaller.install(
            payload: payload, signature: try signature(payload), publicKeyBase64: publicKey,
            domain: domain, support: support, environment: environment()))
    }
}
