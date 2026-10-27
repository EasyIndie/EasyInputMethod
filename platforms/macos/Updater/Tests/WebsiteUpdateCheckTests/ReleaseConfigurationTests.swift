import XCTest
import LampyrisInstallCore

@testable import WebsiteUpdateCheck

final class ReleaseConfigurationTests: XCTestCase {
    func testOnlyFullyConfiguredWebsiteBuildMayCheck() throws {
        let info: [String: Any] = ["LampyrisDistributionChannel": "website",
                                  "SUFeedURL": "https://updates.example.test/feed",
                                  "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
                                  "CFBundleVersion": "10"]
        XCTAssertEqual(try WebsiteReleaseConfiguration.load(info).currentBuild, "10")
        for key in info.keys {
            var missing = info; missing.removeValue(forKey: key)
            XCTAssertThrowsError(try WebsiteReleaseConfiguration.load(missing))
        }
        for channel in ["appstore", "development", ""] {
            var other = info; other["LampyrisDistributionChannel"] = channel
            XCTAssertThrowsError(try WebsiteReleaseConfiguration.load(other))
        }
    }
}
