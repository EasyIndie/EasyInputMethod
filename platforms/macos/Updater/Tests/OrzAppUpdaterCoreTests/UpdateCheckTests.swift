import XCTest
@testable import OrzAppUpdaterCore

final class UpdateCheckTests: XCTestCase {
    private let key = Data(repeating: 7, count: 32).base64EncodedString()
    private func feed(_ versions: [String]) -> Data {
        let signature = Data(repeating: 8, count: 64).base64EncodedString()
        let items = versions.map { "<item><enclosure url=\"https://downloads.example.test/app.zip\" sparkle:version=\"\($0)\" sparkle:edSignature=\"\(signature)\" length=\"100\"/></item>" }.joined()
        return Data("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>\(items)</channel></rss>".utf8)
    }
    func testNumericVersionOrderingAndNoDowngrade() throws {
        XCTAssertEqual(try OrzAppUpdateCheck.newestRelease(in: feed(["9", "11", "10"]), currentBuild: "9")?.build, "11")
        XCTAssertNil(try OrzAppUpdateCheck.newestRelease(in: feed(["1", "2.0"]), currentBuild: "2"))
        XCTAssertEqual(try OrzAppUpdateCheck.newestRelease(in: feed(["2.0.1"]), currentBuild: "2")?.build, "2.0.1")
    }
    func testInvalidAddressesKeysAndBuildsRejected() {
        for address in ["http://example.test/feed", "https://user:pass@example.test/feed", "https://example.test/feed#fragment"] {
            XCTAssertThrowsError(try UpdateCheckConfiguration(feedURL: URL(string: address)!, publicKey: key, currentBuild: "1"))
        }
        XCTAssertThrowsError(try UpdateCheckConfiguration(feedURL: URL(string: "https://example.test")!, publicKey: "invalid", currentBuild: "1"))
        for build in ["", "1.beta", "1..2", "-1", "18446744073709551616"] {
            XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(in: feed(["2"]), currentBuild: build))
        }
    }
    func testUntrustedFeedRejected() throws {
        XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(in: Data(repeating: 0, count: OrzAppUpdateCheck.maximumFeedBytes + 1), currentBuild: "1"))
        for xml in ["<rss>", "<rss/>", "<rss><channel/><channel/></rss>", "<unrelated/>", "<!DOCTYPE rss [<!ENTITY x SYSTEM 'file:///etc/passwd'>]><rss/>", "<rss><channel><item/></channel></rss>"] {
            XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(in: Data(xml.utf8), currentBuild: "1"))
        }
        let bad = String(decoding: feed(["2"]), as: UTF8.self).replacingOccurrences(of: "https://downloads", with: "http://downloads")
        XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(in: Data(bad.utf8), currentBuild: "1"))
    }
    func testRedirectsStayOnHTTPSOriginWithoutStartingRequests() throws {
        let origin = URL(string: "https://updates.example.test/feed")!
        let guardDelegate = RedirectGuard(origin: origin)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let task = session.dataTask(with: origin)
        let response = HTTPURLResponse(url: origin, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for (address, allowed) in [("https://updates.example.test/new-feed", true),
                                    ("http://updates.example.test/feed", false),
                                    ("https://other.example.test/feed", false),
                                    ("https://updates.example.test:444/feed", false)] {
            var accepted = false
            guardDelegate.urlSession(session, task: task, willPerformHTTPRedirection: response,
                newRequest: URLRequest(url: URL(string: address)!)) { accepted = $0 != nil }
            XCTAssertEqual(accepted, allowed)
        }
    }

}
