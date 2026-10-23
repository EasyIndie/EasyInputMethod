import Foundation
import ime

/// 更新来源解析（ADR-264）。
///
/// 来源优先级：用户配置 `update.feed_url`（经 ime-config，空值=未设置）→ 签名包内 `SUFeedURL`。
/// 公钥**永远**来自签名包元数据，用户配置不能替换信任锚。
enum FeedSource {
    static let defaultFeed = URL(string: "https://github.com/EasyIndie/EasyInputMethod/releases/latest/download/appcast.xml")!

    /// 标准配置路径；与应用共用同一份 `config.toml`（不读 UserDefaults、不建第二份配置）。
    static func configPath() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lampyris/config.toml").path
    }

    /// 读取用户配置的更新来源；空值/非法/不可读时回退 `nil`（调用方再用签名默认值）。
    static func configuredFeed(configPath: String? = nil) -> URL? {
        let path = configPath ?? Self.configPath()
        guard ime_config_init(path) == IME_OK,
              let raw = "update.feed_url".withCString({ ime_config_get($0) })
        else { return nil }
        let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, let url = URL(string: value), secure(url) else { return nil }
        return url
    }

    /// 生效来源：用户配置优先，其次签名包默认值。
    static func effectiveFeed(configured: URL?, bundled: URL) -> URL {
        guard let configured, secure(configured) else { return bundled }
        return configured
    }

    /// 读取备用镜像（逗号/空白分隔，最多 8 个，去重保序；非法项忽略）。
    static func configuredMirrors(configPath: String? = nil) -> [URL] {
        let path = configPath ?? Self.configPath()
        guard ime_config_init(path) == IME_OK,
              let raw = "update.feed_mirrors".withCString({ ime_config_get($0) })
        else { return [] }
        var seen = Set<String>()
        var mirrors: [URL] = []
        for part in String(cString: raw).split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let value = String(part)
            guard mirrors.count < 8, seen.insert(value).inserted,
                  let url = URL(string: value), secure(url) else { continue }
            mirrors.append(url)
        }
        return mirrors
    }

    /// 依次尝试的来源：主源（配置/签名默认）→ 镜像；去重后最多 9 个。
    static func effectiveFeeds(configured: URL?, mirrors: [URL], bundled: URL) -> [URL] {
        var feeds: [URL] = []
        var seen = Set<String>()
        for candidate in [effectiveFeed(configured: configured, bundled: bundled)] + mirrors {
            guard secure(candidate), seen.insert(candidate.absoluteString).inserted else { continue }
            feeds.append(candidate)
        }
        return Array(feeds.prefix(9))
    }

    static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil && url.fragment == nil
    }
}
