import Foundation
import OrzAppUpdaterCore

/// Signed build metadata, never an additional user preference store.
enum WebsiteReleaseConfiguration {
    static func load(_ info: [String: Any]) throws -> UpdateCheckConfiguration {
        guard info["LampyrisDistributionChannel"] as? String == "website",
              let address = info["SUFeedURL"] as? String, let feed = URL(string: address),
              let key = info["SUPublicEDKey"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            throw UpdateCheckError.invalidConfiguration
        }
        return try UpdateCheckConfiguration(feedURL: feed, publicKey: key, currentBuild: build)
    }

    /// 只读取网站渠道公钥；验签路径不需要 feed 或构建号，也不联网。
    static func publicKey(_ info: [String: Any]) throws -> String {
        guard info["LampyrisDistributionChannel"] as? String == "website",
              let key = info["SUPublicEDKey"] as? String else {
            throw UpdateCheckError.invalidConfiguration
        }
        return key
    }
}
