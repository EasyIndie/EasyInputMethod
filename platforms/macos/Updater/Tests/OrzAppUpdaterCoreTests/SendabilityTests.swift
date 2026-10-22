import XCTest
@testable import OrzAppUpdaterCore

final class SendabilityTests: XCTestCase {
    private func requireSendable<Value: Sendable>(_ value: Value) -> Value { value }

    func testImmutableMetadataCanCrossConcurrencyBoundary() throws {
        let configuration = try requireSendable(UpdateCheckConfiguration(
            feedURL: URL(string: "https://updates.example.test/feed")!,
            publicKey: Data(repeating: 1, count: 32).base64EncodedString(), currentBuild: "1"))
        XCTAssertEqual(configuration.currentBuild, "1")
        let release = requireSendable(UpdateRelease(build: "2",
            downloadURL: URL(string: "https://updates.example.test/app.zip")!,
            signature: Data(repeating: 2, count: 64), length: 100))
        XCTAssertEqual(release.build, "2")
    }
}
