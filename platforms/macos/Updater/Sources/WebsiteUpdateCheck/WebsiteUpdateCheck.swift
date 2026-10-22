import Foundation
import OrzAppUpdaterCore

// Build metadata belongs to the signed companion bundle, never to user preferences.
@main
struct WebsiteUpdateCheck {
    static func main() async {
        let info = Bundle.main.infoDictionary ?? [:]
        guard CommandLine.arguments.dropFirst() == ["--check"] else {
            print("网站更新检查默认关闭。主动检查请使用 --check；发布配置缺失时不会联网。")
            return
        }
        guard let configuration = try? WebsiteReleaseConfiguration.load(info)
        else {
            FileHandle.standardError.write(Data("更新检查未启用：网站渠道、正式HTTPS地址、公钥或构建号尚未配置。未发送请求。\n".utf8))
            exit(2)
        }
        do {
            if let release = try await OrzAppUpdateCheck.check(configuration) {
                print("发现更新构建：\(release.build)。此结果仅为版本提示；尚未验证或安装下载包。")
            } else {
                print("未发现更高构建版本。")
            }
        } catch {
            // Avoid displaying URLs, credentials or remote response content.
            FileHandle.standardError.write(Data("更新检查失败；输入法仍可离线使用。\n".utf8))
            exit(1)
        }
    }
}
