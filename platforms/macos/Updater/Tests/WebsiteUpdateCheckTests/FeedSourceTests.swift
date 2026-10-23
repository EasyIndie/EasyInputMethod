import Foundation
import XCTest
import ime

@testable import WebsiteUpdateCheck

final class FeedSourceTests: XCTestCase {
    private let bundled = URL(string: "https://github.com/o/r/releases/latest/download/appcast.xml")!

    func testConfiguredFeedWinsWhenSecure() {
        let custom = URL(string: "https://updates.example.com/appcast.xml")!
        XCTAssertEqual(FeedSource.effectiveFeed(configured: custom, bundled: bundled), custom)
    }

    func testInsecureOrMissingFeedFallsBackToBundled() {
        XCTAssertEqual(FeedSource.effectiveFeed(configured: nil, bundled: bundled), bundled)
        XCTAssertEqual(FeedSource.effectiveFeed(
            configured: URL(string: "http://updates.example.com/appcast.xml"), bundled: bundled), bundled)
        XCTAssertEqual(FeedSource.effectiveFeed(
            configured: URL(string: "https://user:pw@updates.example.com/a.xml"), bundled: bundled), bundled)
    }

    func testConfigFileValueIsReadThroughImeConfig() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-feed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("config.toml").path
        XCTAssertEqual(path.withCString { ime_config_init($0) }, IME_OK)
        let custom = "https://updates.example.com/appcast.xml"
        XCTAssertEqual("update.feed_url".withCString { key in
            custom.withCString { value in ime_config_set(key, value) }
        }, IME_OK)
        XCTAssertEqual(FeedSource.configuredFeed(configPath: path)?.absoluteString, custom)
        // 空值表示「使用签名包内的默认（GitHub）来源」。
        XCTAssertEqual("update.feed_url".withCString { key in
            "".withCString { value in ime_config_set(key, value) }
        }, IME_OK)
        XCTAssertNil(FeedSource.configuredFeed(configPath: path))
    }
}
