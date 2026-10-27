import CryptoKit
import Foundation
import XCTest

@testable import LampyrisInstallCore

final class PayloadVerificationTests: XCTestCase {
    private func makeKeyPair() -> (publicKey: String, privateKey: Curve25519.Signing.PrivateKey) {
        let privateKey = Curve25519.Signing.PrivateKey()
        return (privateKey.publicKey.rawRepresentation.base64EncodedString(), privateKey)
    }

    func testValidSignatureVerifies() throws {
        let (publicKey, privateKey) = makeKeyPair()
        let payload = Data("lampyris-update-payload".utf8)
        let signature = try privateKey.signature(for: payload).base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertTrue(try verifier.verify(payload: payload, signatureBase64: signature))
    }

    func testTamperedPayloadFails() throws {
        let (publicKey, privateKey) = makeKeyPair()
        let signature = try privateKey.signature(for: Data("original".utf8)).base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertFalse(try verifier.verify(payload: Data("modified".utf8), signatureBase64: signature))
    }

    func testTamperedSignatureFails() throws {
        let (publicKey, privateKey) = makeKeyPair()
        let payload = Data("payload".utf8)
        var signature = Array(try privateKey.signature(for: payload))
        signature[0] ^= 0x01
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertFalse(try verifier.verify(payload: payload,
                                           signatureBase64: Data(signature).base64EncodedString()))
    }

    func testOtherKeyDoesNotVerify() throws {
        let (publicKey, _) = makeKeyPair()
        let (_, otherPrivate) = makeKeyPair()
        let payload = Data("payload".utf8)
        let signature = try otherPrivate.signature(for: payload).base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertFalse(try verifier.verify(payload: payload, signatureBase64: signature))
    }

    func testInvalidPublicKeyThrows() {
        XCTAssertThrowsError(try PayloadVerifier(publicKeyBase64: "not-base64")) {
            XCTAssertEqual($0 as? PayloadSignatureError, .invalidPublicKey)
        }
        let shortKey = Data(repeating: 0, count: 31).base64EncodedString()
        XCTAssertThrowsError(try PayloadVerifier(publicKeyBase64: shortKey)) {
            XCTAssertEqual($0 as? PayloadSignatureError, .invalidPublicKey)
        }
    }

    func testInvalidSignatureEncodingThrows() throws {
        let (publicKey, _) = makeKeyPair()
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertThrowsError(try verifier.verify(payload: Data(), signatureBase64: "%%%")) {
            XCTAssertEqual($0 as? PayloadSignatureError, .invalidSignature)
        }
        let short = Data(repeating: 0, count: 63).base64EncodedString()
        XCTAssertThrowsError(try verifier.verify(payload: Data(), signatureBase64: short)) {
            XCTAssertEqual($0 as? PayloadSignatureError, .invalidSignature)
        }
    }

    func testFileVerificationAndMissingFile() throws {
        let (publicKey, privateKey) = makeKeyPair()
        let payload = Data("archive-bytes".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lampyris-payload-\(UUID().uuidString)")
        try payload.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let signature = try privateKey.signature(for: payload).base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: publicKey)
        XCTAssertTrue(try verifier.verify(fileAt: url, signatureBase64: signature))
        XCTAssertFalse(try verifier.verify(fileAt: url.appendingPathExtension("missing"),
                                           signatureBase64: signature))
    }
}
