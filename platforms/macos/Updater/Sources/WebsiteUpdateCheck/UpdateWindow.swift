import AppKit
import Foundation
import OrzAppUpdaterCore

/// 最小可用的更新窗口：检查 → 显示新版本 → 下载（进度）→ 验签 → 确认安装 → 结果。
@MainActor
final class UpdateWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let status = NSTextField(labelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let checkButton = NSButton(title: "检查更新", target: nil, action: nil)
    private let installButton = NSButton(title: "下载并安装", target: nil, action: nil)
    private var release: UpdateRelease?
    private var feeds: [URL] = []
    private var running = false

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var domain: URL { FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Input Methods") }
    private var support: URL { FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lampyris/updates") }

    func show() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "萤火虫更新"
        panel.center()
        panel.delegate = self
        let content = NSView()
        panel.contentView = content

        status.font = .systemFont(ofSize: 15, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        checkButton.target = self
        checkButton.action = #selector(checkTapped)
        installButton.target = self
        installButton.action = #selector(installTapped)
        installButton.isEnabled = false

        let stack = NSStackView(views: [status, detail, progress, NSStackView(views: [checkButton, installButton])])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            progress.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            detail.widthAnchor.constraint(equalTo: progress.widthAnchor),
        ])
        window = panel
        status.stringValue = "当前版本 \(versionText)"
        detail.stringValue = "默认使用 GitHub 发布源；可在设置 → 更新里配置镜像。"
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var versionText: String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "v\(version)（build \(build)）"
    }

    private func setBusy(_ busy: Bool) {
        running = busy
        checkButton.isEnabled = !busy
        installButton.isEnabled = !busy && release != nil
        progress.isIndeterminate = busy && release == nil
        if busy && release == nil { progress.startAnimation(nil) }
        if !busy { progress.stopAnimation(nil) }
    }

    private func fail(_ message: String) {
        setBusy(false)
        status.stringValue = "更新失败"
        detail.stringValue = message
    }

    @objc private func checkTapped() {
        guard !running else { return }
        release = nil
        setBusy(true)
        status.stringValue = "正在检查更新…"
        detail.stringValue = "依次尝试默认源与镜像。"
        Task { @MainActor in
            do {
                guard let bundled = WebsiteReleaseConfiguration.bundledFeed(info) else {
                    return fail("缺少签名包内的更新源")
                }
                let feeds = FeedSource.effectiveFeeds(configured: FeedSource.configuredFeed(),
                                                      mirrors: FeedSource.configuredMirrors(),
                                                      bundled: bundled)
                let configurations = try WebsiteReleaseConfiguration.configurations(info, feeds: feeds)
                var matched: (UpdateRelease, URL)?
                var failures = 0
                for configuration in configurations {
                    do {
                        if let release = try await OrzAppUpdateCheck.check(configuration) {
                            matched = (release, configuration.feedURL)
                            break
                        }
                        setBusy(false)
                        status.stringValue = "已是最新版本"
                        detail.stringValue = "当前 \(versionText)，没有更高构建。"
                        return
                    } catch {
                        failures += 1
                        continue
                    }
                }
                guard let (release, source) = matched else {
                    return fail("所有更新来源均不可用（\(failures) 个）。输入法仍可离线使用。")
                }
                self.release = release
                self.feeds = [source]
                setBusy(false)
                status.stringValue = "发现新版本 build \(release.build)"
                detail.stringValue = String(format: "下载大小约 %.1f MB，来源 %@；下载后会先验签，再询问是否安装。",
                                            Double(release.length) / 1_048_576.0,
                                            source.host ?? "未知")
            } catch {
                fail("更新配置不完整或检查失败。")
            }
        }
    }

    @objc private func installTapped() {
        guard let release, !running else { return }
        guard let key = info["SUPublicEDKey"] as? String else { return fail("缺少公钥") }
        setBusy(true)
        status.stringValue = "正在下载…"
        progress.isIndeterminate = false
        progress.doubleValue = 0
        Task { @MainActor in
            do {
                let downloader = UpdateDownloader()
                let payload = try await downloader.download(release.downloadURL) { written, expected in
                    Task { @MainActor in
                        if expected > 0 {
                            self.progress.doubleValue = min(1, Double(written) / Double(expected))
                        }
                    }
                }
                status.stringValue = "正在验证签名…"
                let signature = release.signature.base64EncodedString()
                let verifier = try PayloadVerifier(publicKeyBase64: key)
                guard try verifier.verify(fileAt: payload, signatureBase64: signature) else {
                    return fail("负载签名无效，未安装。")
                }
                let alert = NSAlert()
                alert.messageText = "安装 build \(release.build)？"
                alert.informativeText = "将替换当前输入法（会短暂停止宿主），旧版本自动备份；失败会回滚。"
                alert.addButton(withTitle: "安装")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    setBusy(false)
                    status.stringValue = "已取消"
                    return
                }
                status.stringValue = "正在安装…"
                progress.isIndeterminate = true
                progress.startAnimation(nil)
                let receipt = try UpdateInstaller.install(
                    payload: payload, signature: signature, publicKeyBase64: key,
                    domain: domain, support: support,
                    environment: DefaultInstallEnvironment.make())
                setBusy(false)
                status.stringValue = "已安装 build \(release.build)"
                detail.stringValue = "旧版本备份：\(receipt.previous ?? "无")"
            } catch {
                fail("安装失败：\(error.localizedDescription)")
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.terminate(nil)
    }
}

@MainActor
final class UpdateAppDelegate: NSObject, NSApplicationDelegate {
    private let controller = UpdateWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) { controller.show() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
