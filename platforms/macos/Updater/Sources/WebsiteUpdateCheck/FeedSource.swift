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

    static func secure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty
            && url.user == nil && url.password == nil && url.fragment == nil
    }
}
