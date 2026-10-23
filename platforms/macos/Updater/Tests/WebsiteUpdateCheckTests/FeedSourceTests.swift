import Foundation
import XCTest
import ime

@testable import WebsiteUpdateCheck

final class FeedSourceTests: XCTestCase {
    private let bundled = URL(string: "https://github.com/o/r/releases/latest/download/appcast.xml")!

    /// ime-config 的 PATH_OVERRIDE 每个进程只生效一次，测试共用一个临时配置。
    private static let shared: String = {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-feed-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("config.toml").path
        _ = path.withCString { ime_config_init($0) }
        return path
    }()

    private func setConfig(_ key: String, _ value: String) {
        XCTAssertEqual(key.withCString { k in
            value.withCString { v in ime_config_set(k, v) }
        }, IME_OK)
    }

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

    func testMirrorsAreOrderedDedupedAndBounded() {
        let bundled = URL(string: "https://github.com/o/r/releases/latest/download/appcast.xml")!
        let primary = URL(string: "https://updates.example.com/appcast.xml")!
        let mirrors = [
            URL(string: "https://cn.example.com/appcast.xml")!,
            URL(string: "https://primary.example.com/appcast.xml")!,
            primary,
        ]
        let feeds = FeedSource.effectiveFeeds(configured: primary, mirrors: mirrors, bundled: bundled)
        XCTAssertEqual(feeds.map(\.absoluteString),
                       ["https://updates.example.com/appcast.xml",
                        "https://cn.example.com/appcast.xml",
                        "https://primary.example.com/appcast.xml"])
    }

    func testInsecureMirrorsAreIgnored() {
        let bundled = URL(string: "https://github.com/o/r/releases/latest/download/appcast.xml")!
        let feeds = FeedSource.effectiveFeeds(
            configured: nil,
            mirrors: [URL(string: "http://cn.example.com/appcast.xml")!,
                      URL(string: "https://user:pw@cn.example.com/a.xml")!],
            bundled: bundled)
        XCTAssertEqual(feeds.map(\.absoluteString), [bundled.absoluteString])
    }

    func testConfigFileMirrorsAreReadThroughImeConfig() throws {
        let list = "https://cn.example.com/appcast.xml,https://mirror.example.com/appcast.xml"
        setConfig("update.feed_mirrors", list)
        XCTAssertEqual(FeedSource.configuredMirrors(configPath: Self.shared).map(\.absoluteString),
                       ["https://cn.example.com/appcast.xml", "https://mirror.example.com/appcast.xml"])
        setConfig("update.feed_mirrors", "")
    }

    func testConfigFileValueIsReadThroughImeConfig() throws {
        let custom = "https://updates.example.com/appcast.xml"
        setConfig("update.feed_url", custom)
        XCTAssertEqual(FeedSource.configuredFeed(configPath: Self.shared)?.absoluteString, custom)
        // 空值表示「使用签名包内的默认（GitHub）来源」。
        setConfig("update.feed_url", "")
        XCTAssertNil(FeedSource.configuredFeed(configPath: Self.shared))
    }
}
