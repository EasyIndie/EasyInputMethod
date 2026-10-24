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
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "更新"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = NSView()
        panel.contentView = content

        let iconView = NSImageView()
        iconView.image = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.setAccessibilityLabel("萤火虫图标")
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 58).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 58).isActive = true

        let title = NSTextField(labelWithString: "萤火虫")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        let version = NSTextField(labelWithString: "当前版本 \(versionText)")
        version.font = .systemFont(ofSize: 12)
        version.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [title, version])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        let header = NSStackView(views: [iconView, titleStack])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true

        status.font = .systemFont(ofSize: 15, weight: .semibold)
        status.lineBreakMode = .byTruncatingTail
        status.stringValue = "准备就绪"
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        detail.stringValue = "默认使用 GitHub 发布源；可在设置 → 更新里配置镜像。"

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.doubleValue = 0
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 8).isActive = true

        checkButton.bezelStyle = .rounded
        checkButton.controlSize = .large
        checkButton.target = self
        checkButton.action = #selector(checkTapped)
        installButton.bezelStyle = .rounded
        installButton.controlSize = .large
        installButton.bezelColor = .controlAccentColor
        installButton.keyEquivalent = "\r"
        installButton.target = self
        installButton.action = #selector(installTapped)
        installButton.isEnabled = false
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, checkButton, installButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let footer = NSTextField(labelWithString: "安装前会用内置公钥验证更新包；输入法核心始终离线。")
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [header, separator, status, detail, progress, buttons, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 262)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            progress.widthAnchor.constraint(equalTo: detail.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: detail.widthAnchor),
            footer.widthAnchor.constraint(equalTo: detail.widthAnchor),
        ])
        panel.setContentSize(NSSize(width: 520, height: 262))
        stack.layoutSubtreeIfNeeded()
        panel.center()

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var versionText: String {
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) · 构建 \(build)"
    }

    private func setBusy(_ busy: Bool) {
        running = busy
        checkButton.isEnabled = !busy
        installButton.isEnabled = !busy && release != nil
        if !busy {
            progress.stopAnimation(nil)
            progress.isIndeterminate = false
            progress.isHidden = true
        }
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
                status.stringValue = "发现新版本 · 构建 \(release.build)"
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
        progress.isHidden = false
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
                guard try verifier.verify(fileAt: payload.url, signatureBase64: signature) else {
                    return fail("负载签名无效，未安装。")
                }
                let alert = NSAlert()
                alert.messageText = "安装构建 \(release.build)？"
                alert.informativeText = "将替换当前输入法（会短暂停止宿主），旧版本自动备份；失败会回滚。"
                alert.addButton(withTitle: "安装")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else {
                    setBusy(false)
                    status.stringValue = "已取消"
                    return
                }
                status.stringValue = "正在安装…"
                progress.doubleValue = 1
                progress.isIndeterminate = true
                progress.startAnimation(nil)
                let receipt = try UpdateInstaller.install(
                    payload: payload.url, signature: signature, publicKeyBase64: key,
                    domain: domain, support: support,
                    environment: DefaultInstallEnvironment.make())
                setBusy(false)
                status.stringValue = "已安装构建 \(release.build)"
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
        controller.show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
