import Foundation
import XCTest

import LampyrisInstallCore

@testable import WebsiteUpdateCheck

/// 报告214：更新窗口的「当前版本」必须读**已安装宿主**，且安装成功后能刷新——
/// 否则老更新程序装完新宿主仍显示旧版本，用户会断定「没更新」。
final class InstalledVersionTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for url in roots { try? FileManager.default.removeItem(at: url) }
        roots = []
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-home-\(UUID().uuidString.lowercased())")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        roots.append(home)
        return home
    }

    @discardableResult
    private func installHost(in home: URL, version: String?, build: String?) throws -> URL {
        let app = home.appendingPathComponent("Library/Input Methods/Lampyris.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"),
                                                withIntermediateDirectories: true)
        var plist: [String: Any] = ["CFBundleIdentifier": "cn.jokerhub.inputmethod.Lampyris"]
        if let version { plist["CFBundleShortVersionString"] = version }
        if let build { plist["CFBundleVersion"] = build }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    private func productionLocation(home: URL) throws -> InstallLocation {
        try InstallLocation.resolve(info: [:], home: home)
    }

    func testReportsTheInstalledHostVersion() throws {
        let home = try makeHome()
        try installHost(in: home, version: "0.1.15", build: "24")
        XCTAssertEqual(InstalledVersion.installed(try productionLocation(home: home)), "0.1.15 · 构建 24")
    }

    func testFollowsTheHostAfterAnUpgrade() throws {
        let home = try makeHome()
        try installHost(in: home, version: "0.1.14", build: "23")
        let location = try productionLocation(home: home)
        XCTAssertEqual(InstalledVersion.installed(location), "0.1.14 · 构建 23")
        // 升级写入新的宿主后，同一个 location 立即读出新的构建号。
        try installHost(in: home, version: "0.1.15", build: "24")
        XCTAssertEqual(InstalledVersion.installed(location), "0.1.15 · 构建 24")
    }

    func testMissingHostIsUnknown() throws {
        let home = try makeHome()
        XCTAssertEqual(InstalledVersion.installed(try productionLocation(home: home)), "未知")
    }

    func testIncompleteBundleIsUnknown() throws {
        let home = try makeHome()
        let app = try installHost(in: home, version: "0.1.15", build: nil)
        XCTAssertEqual(InstalledVersion.text(bundleAt: app), "未知")
        XCTAssertEqual(InstalledVersion.text(bundleAt: nil), "未知")
    }

    func testIgnoresTheUpdaterOwnBundle() throws {
        // 更新程序自己的 Bundle.main 是 0.1.14/23 时，显示的仍应是已安装宿主。
        let home = try makeHome()
        try installHost(in: home, version: "0.1.15", build: "24")
        let location = try productionLocation(home: home)
        XCTAssertNotEqual(InstalledVersion.installed(location), "未知")
        XCTAssertEqual(InstalledVersion.installed(location),
                       InstalledVersion.text(bundleAt: location.domain.appendingPathComponent("Lampyris.app")))
    }
}
