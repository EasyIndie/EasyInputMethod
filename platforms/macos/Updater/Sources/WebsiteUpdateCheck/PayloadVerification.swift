import CryptoKit
import Foundation

/// 更新负载的 Ed25519 签名校验（ADR-256）。
///
/// 只做纯离线校验：调用方负责下载与流程控制，本类型不联网、不写配置。
/// `publicKeyBase64` 与 `signatureBase64` 都是标准 Base64；公钥是 32 字节
/// Curve25519 原始公钥，签名是 64 字节 Ed25519 签名，签名对象为负载原始字节。
public enum PayloadSignatureError: Error, Equatable {
    /// 公钥不是合法的 32 字节 Base64。
    case invalidPublicKey
    /// 签名不是合法的 Base64 或长度不为 64 字节。
    case invalidSignature
}

public struct PayloadVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    public init(publicKeyBase64: String) throws {
        guard let raw = Data(base64Encoded: publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              raw.count == 32,
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else {
            throw PayloadSignatureError.invalidPublicKey
        }
        publicKey = key
    }

    /// 校验负载原始字节；签名无效返回 `false`，编码/长度错误抛错。
    public func verify(payload: Data, signatureBase64: String) throws -> Bool {
        guard let signature = Data(base64Encoded: signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)),
              signature.count == 64
        else {
            throw PayloadSignatureError.invalidSignature
        }
        return publicKey.isValidSignature(signature, for: payload)
    }

    /// 校验磁盘上的负载文件；读取失败按无效签名处理，不向外抛路径细节。
    public func verify(fileAt url: URL, signatureBase64: String) throws -> Bool {
        guard let payload = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }
        return try verify(payload: payload, signatureBase64: signatureBase64)
    }
}
