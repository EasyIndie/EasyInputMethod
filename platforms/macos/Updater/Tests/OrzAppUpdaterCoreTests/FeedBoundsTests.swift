import XCTest
@testable import OrzAppUpdaterCore

final class FeedBoundsTests: XCTestCase {
    private let signature = Data(repeating: 8, count: 64).base64EncodedString()
    private func enclosure(_ attributes: String = "") -> String {
        "<enclosure url=\"https://updates.example.test/app.zip\" sparkle:version=\"2\" sparkle:edSignature=\"\(signature)\" length=\"100\" \(attributes)/>"
    }
    private func feed(_ body: String) -> Data {
        Data("<rss xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\"><channel>\(body)</channel></rss>".utf8)
    }
    func testDepthItemAndEnclosureBounds() {
        let item = "<item>\(enclosure())</item>"
        XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(
            in: feed(String(repeating: item, count: 1001)), currentBuild: "1"))
        XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(
            in: feed(String(repeating: "<x>", count: 17) + String(repeating: "</x>", count: 17)), currentBuild: "1"))
        XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(
            in: feed("<item>\(enclosure())\(enclosure())</item>"), currentBuild: "1"))
    }
    func testMalformedSignatureLengthAndBuildAreRejected() {
        let valid = "<item>\(enclosure())</item>"
        for body in [valid.replacingOccurrences(of: signature, with: Data(repeating: 8, count: 63).base64EncodedString()),
                     valid.replacingOccurrences(of: "length=\"100\"", with: "length=\"0\""),
                     valid.replacingOccurrences(of: "sparkle:version=\"2\"", with: "sparkle:version=\"2..1\"")] {
            XCTAssertThrowsError(try OrzAppUpdateCheck.newestRelease(in: feed(body), currentBuild: "1"))
        }
    }
}
