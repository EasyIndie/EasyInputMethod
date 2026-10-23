import Foundation
import OrzAppUpdaterCore

// Build metadata belongs to the signed companion bundle, never to user preferences.
@main
struct WebsiteUpdateCheck {
    static func main() async {
        let info = Bundle.main.infoDictionary ?? [:]
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "--verify-payload" {
            let values = Array(arguments.dropFirst())
            guard values.count == 2, let key = try? WebsiteReleaseConfiguration.publicKey(info) else {
                FileHandle.standardError.write(Data("更新检查未启用：网站渠道公钥未配置。未发送请求。\n".utf8))
                exit(2)
            }
            do {
                let verifier = try PayloadVerifier(publicKeyBase64: key)
                let payload = URL(fileURLWithPath: values[0])
                if try verifier.verify(fileAt: payload, signatureBase64: values[1]) {
                    print("负载签名验证通过；尚未安装。")
                } else {
                    FileHandle.standardError.write(Data("负载签名无效；不安装。\n".utf8))
                    exit(1)
                }
            } catch {
                FileHandle.standardError.write(Data("签名参数无效；不安装。\n".utf8))
                exit(1)
            }
            return
        }
        guard arguments == ["--check"] else {
            print("网站更新检查默认关闭。主动检查请使用 --check；发布配置缺失时不会联网。")
            return
        }
        guard let bundled = WebsiteReleaseConfiguration.bundledFeed(info) else {
            FileHandle.standardError.write(Data("更新检查未启用：缺少签名包内的默认来源。未发送请求。\n".utf8))
            exit(2)
        }
        let feeds = FeedSource.effectiveFeeds(configured: FeedSource.configuredFeed(),
                                              mirrors: FeedSource.configuredMirrors(),
                                              bundled: bundled)
        let configurations: [UpdateCheckConfiguration]
        do {
            configurations = try WebsiteReleaseConfiguration.configurations(info, feeds: feeds)
        } catch {
            FileHandle.standardError.write(Data("更新检查未启用：发布配置不完整。未发送请求。\n".utf8))
            exit(2)
        }
        var failures = 0
        for configuration in configurations {
            do {
                if let release = try await OrzAppUpdateCheck.check(configuration) {
                    print("发现更新构建：\(release.build)（来源 \(configuration.feedURL.host ?? "未知")）。此结果仅为版本提示；尚未验证或安装下载包。")
                } else {
                    print("未发现更高构建版本。")
                }
                return
            } catch {
                failures += 1
                continue
            }
        }
        FileHandle.standardError.write(Data("所有更新来源均不可用（已尝试 \(failures) 个）；输入法仍可离线使用。\n".utf8))
        exit(1)
    }
}
