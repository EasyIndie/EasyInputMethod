import AppKit
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
        if arguments.first == "--drill-run" {
            // ADR-288: only an isolated test build may exercise this headless drill path.
            guard arguments.count == 2 else {
                FileHandle.standardError.write(Data("用法：--drill-run install|cancel|tamper\n".utf8))
                exit(2)
            }
            await runDrill(mode: arguments[1])
            return
        }
        if arguments == ["--ui"] {
            let app = NSApplication.shared
            let delegate = UpdateAppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
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

extension WebsiteUpdateCheck {
    /// Exercises the real feed/download/verify/install path without any UI, for isolated drill use only.
    static func runDrill(mode: String) async {
        let info = Bundle.main.infoDictionary ?? [:]
        func fail(_ message: String) -> Never {
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
        guard let location = try? InstallLocation.resolve(info: info), location.isolated else {
            fail("drill 只允许隔离测试构建运行；未发送请求。")
        }
        guard let bundled = WebsiteReleaseConfiguration.bundledFeed(info) else {
            fail("缺少签名包内的更新源。")
        }
        let feeds = FeedSource.effectiveFeeds(configured: FeedSource.configuredFeed(),
                                              mirrors: [], bundled: bundled)
        let configurations: [UpdateCheckConfiguration]
        do {
            configurations = try WebsiteReleaseConfiguration.configurations(info, feeds: feeds)
        } catch {
            fail("更新配置不完整。")
        }
        print("feed=\(configurations[0].feedURL.absoluteString)")
        print("target=\(location.target.identity) domain=\(location.domain.path)")
        let release: UpdateRelease?
        do {
            release = try await OrzAppUpdateCheck.check(configurations[0])
        } catch {
            fail("检查更新失败：\(error.localizedDescription)")
        }
        guard let release else {
            print("result=up-to-date")
            return
        }
        print("release_build=\(release.build) length=\(release.length)")
        guard let key = info["SUPublicEDKey"] as? String else {
            fail("缺少公钥。")
        }
        let downloader = UpdateDownloader()
        var payload: DownloadedPayload?
        do {
            payload = try await downloader.download(release.downloadURL) { _, _ in }
        } catch {
            fail("下载失败：\(error.localizedDescription)")
        }
        guard let downloaded = payload else { fail("下载失败：无负载") }
        let folder = downloaded.url.deletingLastPathComponent()
        let manager = FileManager.default
        print("download_private=\(manager.fileExists(atPath: folder.path))")
        let signature = release.signature.base64EncodedString()
        let verifier: PayloadVerifier
        do {
            verifier = try PayloadVerifier(publicKeyBase64: key)
        } catch {
            fail("公钥无效。")
        }
        if mode == "tamper" {
            if let handle = try? FileHandle(forWritingTo: downloaded.url) {
                handle.seekToEndOfFile()
                handle.write(Data([0x00]))
                try? handle.close()
            }
        }
        let verified: Bool
        do {
            verified = try verifier.verify(fileAt: downloaded.url, signatureBase64: signature)
        } catch {
            fail("验签异常：\(error.localizedDescription)")
        }
        print("signature=\(verified ? "valid" : "invalid")")
        if !verified {
            payload = nil
            print("temp_after_release=\(manager.fileExists(atPath: folder.path))")
            print("result=rejected")
            return
        }
        if mode == "cancel" {
            payload = nil
            print("temp_after_cancel=\(manager.fileExists(atPath: folder.path))")
            print("result=cancelled")
            return
        }
        guard mode == "install" else {
            payload = nil
            fail("未知 drill 模式：\(mode)")
        }
        do {
            let receipt = try UpdateInstaller.install(
                payload: downloaded.url, signature: signature, publicKeyBase64: key,
                domain: location.domain, support: location.support,
                environment: DefaultInstallEnvironment.make(target: location.target),
                target: location.target)
            print("installed_exec=\(receipt.installedExecutableSHA256)")
            print("previous=\(receipt.previous ?? "none")")
            print("result=installed")
        } catch {
            fail("安装失败：\(error.localizedDescription)")
        }
        payload = nil
        print("temp_after_install=\(manager.fileExists(atPath: folder.path))")
    }
}
