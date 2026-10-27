import AppKit
import Foundation
import LampyrisInstallCore
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
        guard let location = try? InstallLocation.resolve(info: info), location.isolated else {
            drillFail("drill 只允许隔离测试构建运行；未发送请求。")
        }
        guard let release = await drillRelease(info: info, location: location),
              let key = info["SUPublicEDKey"] as? String else {
            return
        }
        switch mode {
        case "rollback":
            do {
                let (restored, folder) = try await drillRollback(release: release, key: key, location: location)
                print("restored_exec=\(restored)")
                print("temp_after_install=\(FileManager.default.fileExists(atPath: folder.path))")
                print("result=rolled-back")
            } catch {
                drillFail("回滚演练失败：\(error.localizedDescription)")
            }
        case "cancel", "tamper":
            let (folder, verified) = await drillVerifyOnly(mode: mode, release: release, key: key)
            print("signature=\(verified ? "valid" : "invalid")")
            // DownloadedPayload was released before this line, so a surviving directory is a leak.
            print("temp_after_release=\(FileManager.default.fileExists(atPath: folder.path))")
            print("result=\(verified ? "cancelled" : "rejected")")
        case "install":
            do {
                let (receipt, folder) = try await drillInstall(release: release, key: key, location: location)
                print("installed_exec=\(receipt.installedExecutableSHA256)")
                print("previous=\(receipt.previous ?? "none")")
                print("temp_after_install=\(FileManager.default.fileExists(atPath: folder.path))")
                print("result=installed")
            } catch {
                drillFail("安装失败：\(error.localizedDescription)")
            }
        default:
            drillFail("未知 drill 模式：\(mode)")
        }
    }

    static func drillFail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    static func drillRelease(info: [String: Any], location: InstallLocation) async -> UpdateRelease? {
        guard let bundled = WebsiteReleaseConfiguration.bundledFeed(info) else {
            drillFail("缺少签名包内的更新源。")
        }
        let feeds = FeedSource.effectiveFeeds(configured: FeedSource.configuredFeed(),
                                              mirrors: [], bundled: bundled)
        let configurations: [UpdateCheckConfiguration]
        do {
            configurations = try WebsiteReleaseConfiguration.configurations(info, feeds: feeds)
        } catch {
            drillFail("更新配置不完整。")
        }
        print("feed=\(configurations[0].feedURL.absoluteString)")
        print("target=\(location.target.identity) domain=\(location.domain.path)")
        let release: UpdateRelease?
        do {
            release = try await OrzAppUpdateCheck.check(configurations[0])
        } catch {
            drillFail("检查更新失败：\(error.localizedDescription)")
        }
        guard let release else {
            print("result=up-to-date")
            return nil
        }
        print("release_build=\(release.build) length=\(release.length)")
        return release
    }

    static func drillVerifyOnly(mode: String, release: UpdateRelease, key: String)
        async -> (URL, Bool)
    {
        let downloader = UpdateDownloader()
        let folder: URL
        let verified: Bool
        do {
            var payload: DownloadedPayload? = try await downloader.download(release.downloadURL) { _, _ in }
            guard let downloaded = payload else { drillFail("下载失败：无负载") }
            folder = downloaded.url.deletingLastPathComponent()
            print("download_private=\(FileManager.default.fileExists(atPath: folder.path))")
            if mode == "tamper", let handle = try? FileHandle(forWritingTo: downloaded.url) {
                handle.seekToEndOfFile()
                handle.write(Data([0x00]))
                try? handle.close()
            }
            let verifier: PayloadVerifier
            do {
                verifier = try PayloadVerifier(publicKeyBase64: key)
                verified = try verifier.verify(fileAt: downloaded.url,
                                               signatureBase64: release.signature.base64EncodedString())
            } catch {
                drillFail("验签异常：\(error.localizedDescription)")
            }
            payload = nil
        } catch {
            drillFail("下载失败：\(error.localizedDescription)")
        }
        return (folder, verified)
    }

    static func drillInstall(release: UpdateRelease, key: String, location: InstallLocation)
        async throws -> (InstallReceipt, URL)
    {
        let downloader = UpdateDownloader()
        var payload: DownloadedPayload? = try await downloader.download(release.downloadURL) { _, _ in }
        guard let downloaded = payload else { throw InstallError.payloadMissing("下载失败") }
        let folder = downloaded.url.deletingLastPathComponent()
        print("download_private=\(FileManager.default.fileExists(atPath: folder.path))")
        let signature = release.signature.base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: key)
        let verified = try verifier.verify(fileAt: downloaded.url, signatureBase64: signature)
        print("signature=\(verified ? "valid" : "invalid")")
        guard verified else {
            payload = nil
            throw InstallError.candidateInvalid("负载签名无效")
        }
        let receipt = try UpdateInstaller.install(
            payload: downloaded.url, signature: signature, publicKeyBase64: key,
            domain: location.domain, support: location.support,
            environment: DefaultInstallEnvironment.make(target: location.target),
            target: location.target)
        payload = nil
        return (receipt, folder)
    }
}

extension WebsiteUpdateCheck {
    /// Final state of the install slot plus whether the leftover work directory is gone.
    static func drillInstallState(location: InstallLocation) -> (exec: String, workDirs: Int) {
        let installed = location.domain.appendingPathComponent(location.target.bundleName)
        let exec = installed.appendingPathComponent(location.target.executablePath)
        let sha = (try? UpdateInstaller.sha256(exec)) ?? "missing"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: location.support.path)) ?? []
        let workDirs = entries.filter { $0.hasPrefix("upgrade-") }.count + entries.filter { $0 == "staging" }.count
        return (sha, workDirs)
    }

    /// Injects a failure after the candidate is placed, to prove the real rollback path restores the old bundle.
    static func drillRollback(release: UpdateRelease, key: String, location: InstallLocation)
        async throws -> (String, URL)
    {
        let before = drillInstallState(location: location)
        print("before_exec=\(before.exec) work_dirs=\(before.workDirs)")
        let downloader = UpdateDownloader()
        var payload: DownloadedPayload? = try await downloader.download(release.downloadURL) { _, _ in }
        guard let downloaded = payload else { throw InstallError.payloadMissing("下载失败") }
        let folder = downloaded.url.deletingLastPathComponent()
        let signature = release.signature.base64EncodedString()
        let verifier = try PayloadVerifier(publicKeyBase64: key)
        guard try verifier.verify(fileAt: downloaded.url, signatureBase64: signature) else {
            throw InstallError.candidateInvalid("负载签名无效")
        }
        let base = DefaultInstallEnvironment.make(target: location.target)
        let counter = DrillCounter()
        let environment = InstallEnvironment(validateCandidate: { app in
            try base.validateCandidate(app)
            // Second call happens after the bundle is moved into place.
            if counter.increment() >= 2 {
                throw InstallError.candidateInvalid("drill 注入：落地后校验失败")
            }
        }, stopHost: base.stopHost)
        defer { payload = nil }
        do {
            _ = try UpdateInstaller.install(
                payload: downloaded.url, signature: signature, publicKeyBase64: key,
                domain: location.domain, support: location.support,
                environment: environment, target: location.target)
        } catch {
            let after = drillInstallState(location: location)
            print("after_exec=\(after.exec) work_dirs=\(after.workDirs)")
            print("injected_error=\(error.localizedDescription)")
            guard after.exec == before.exec, after.workDirs == before.workDirs else {
                throw InstallError.replaceFailed("回滚未恢复到演练前状态")
            }
            payload = nil
            return (after.exec, folder)
        }
        throw InstallError.replaceFailed("演练本应失败却安装成功")
    }
}

final class DrillCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
