import Foundation
import OrzAppUpdaterCore

/// Signed build metadata, never an additional user preference store.
enum WebsiteReleaseConfiguration {
    static func load(_ info: [String: Any], configuredFeed: URL? = FeedSource.configuredFeed())
        throws -> UpdateCheckConfiguration
    {
        guard let bundled = bundledFeed(info) else { throw UpdateCheckError.invalidConfiguration }
        let feed = FeedSource.effectiveFeed(configured: configuredFeed, bundled: bundled)
        return try configurations(info, feeds: [feed])[0]
    }

    /// 主源与镜像按顺序构造配置；公钥/渠道/构建号只校验一次。
    static func configurations(_ info: [String: Any], feeds: [URL]) throws
        -> [UpdateCheckConfiguration]
    {
        guard info["LampyrisDistributionChannel"] as? String == "website",
              let key = info["SUPublicEDKey"] as? String,
              let build = info["CFBundleVersion"] as? String,
              !feeds.isEmpty else {
            throw UpdateCheckError.invalidConfiguration
        }
        return try feeds.map {
            try UpdateCheckConfiguration(feedURL: $0, publicKey: key, currentBuild: build)
        }
    }

    static func bundledFeed(_ info: [String: Any]) -> URL? {
        (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
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
