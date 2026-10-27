import AppKit
import Foundation
import LampyrisInstallCore
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
    /// 自更新后当前进程仍是旧代码（ADR-295）：给一个显式的重新打开入口，立即生效。
    private let relaunchButton = NSButton(title: "重新打开更新程序", target: nil, action: nil)
    /// 已安装版本自带卸载（ADR-296），不需要用户保留 DMG。
    private let uninstallButton = NSButton(title: "卸载萤火虫…", target: nil, action: nil)
    private var release: UpdateRelease?
    private var feeds: [URL] = []
    private var running = false
    private let location: InstallLocation?
    private let locationError: String?

    override init() {
        do {
            let resolved = try InstallLocation.resolve(info: Bundle.main.infoDictionary ?? [:])
            location = resolved
            locationError = nil
        } catch {
            location = nil
            locationError = error.localizedDescription
        }
        super.init()
    }

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

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
        relaunchButton.bezelStyle = .rounded
        relaunchButton.controlSize = .large
        relaunchButton.target = self
        relaunchButton.action = #selector(relaunchTapped)
        relaunchButton.isHidden = true
        uninstallButton.bezelStyle = .rounded
        uninstallButton.controlSize = .large
        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallTapped)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [uninstallButton, spacer, checkButton, relaunchButton,
                                          installButton])
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
        if let locationError {
            setBusy(false)
            status.stringValue = "更新已停用"
            detail.stringValue = locationError
            checkButton.isEnabled = false
        }
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
        relaunchButton.keyEquivalent = ""
        status.stringValue = "更新失败"
        detail.stringValue = message
    }

    @objc private func checkTapped() {
        guard !running else { return }
        guard location != nil else { return fail(locationError ?? "更新安装位置无效") }
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
        guard let release, !running, let location else { return }
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
                let target = location.target
                let receipt = try UpdateInstaller.install(
                    payload: payload.url, signature: signature, publicKeyBase64: key,
                    domain: location.domain, support: location.support,
                    environment: DefaultInstallEnvironment.make(target: target), target: target,
                    selfUpdate: location.applications.map {
                        UpdateInstaller.SelfUpdate(
                            directory: $0,
                            environment: DefaultInstallEnvironment.make(target: .updater))
                    })
                setBusy(false)
                status.stringValue = "已安装构建 \(release.build)"
                detail.stringValue = "旧版本备份：\(receipt.previous ?? "无")"
                    + (receipt.updaterBundle.map {
                        "\n更新程序已同步到 \($0)；点「重新打开更新程序」立即使用新版本。"
                    } ?? "")
                if receipt.updaterBundle != nil {
                    relaunchButton.isHidden = false
                    relaunchButton.isEnabled = true
                    relaunchButton.keyEquivalent = "\r"
                    installButton.isEnabled = false
                }
            } catch {
                fail("安装失败：\(error.localizedDescription)")
            }
        }
    }

    /// 卸载：确认 → 停宿主 → 切回 ABC → 删除/保留数据 → 退出后由 detached shell 删除自己。
    @objc private func uninstallTapped() {
        guard !running, let location else { return }
        guard !location.isolated, let applications = location.applications else {
            return fail("隔离构建不允许卸载生产安装")
        }
        let choice = NSAlert()
        choice.messageText = "卸载萤火虫？"
        choice.informativeText = "将移除输入法与更新程序，切回 ABC 并禁用输入源。"
            + "\n默认保留 config.toml 与个人词库；卸载后需要注销重新登录。"
        choice.addButton(withTitle: "卸载（保留配置与词库）")
        choice.addButton(withTitle: "彻底清理全部数据…")
        choice.addButton(withTitle: "取消")
        var purge = false
        switch choice.runModal() {
        case .alertFirstButtonReturn: purge = false
        case .alertSecondButtonReturn:
            let confirm = NSAlert()
            confirm.messageText = "彻底清理全部数据？"
            confirm.informativeText = "配置、个人词库、更新备份与缓存都会被删除，且无法恢复。"
            confirm.addButton(withTitle: "全部删除")
            confirm.addButton(withTitle: "取消")
            confirm.alertStyle = .warning
            guard confirm.runModal() == .alertFirstButtonReturn else { return }
            purge = true
        default: return
        }
        running = true
        setBusy(true)
        uninstallButton.isEnabled = false
        status.stringValue = "正在卸载…"
        detail.stringValue = "切回 ABC、停止输入法并移除文件。"
        let paths = UninstallPaths(home: location.home, domain: location.domain,
                                   applications: applications, support: location.support)
        let selfBundle = Bundle.main.bundleURL
        let mode: UninstallMode = purge ? .removeAll : .keepData
        Task.detached {
            let result: Result<UninstallOutcome, Error>
            do {
                result = .success(try UninstallRunner.run(mode: mode, paths: paths,
                                                          selfBundle: selfBundle))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.finishUninstall(result, purge: purge)
            }
        }
    }

    private func finishUninstall(_ result: Result<UninstallOutcome, Error>, purge: Bool) {
        switch result {
        case .success(let outcome):
            status.stringValue = purge ? "已彻底清理" : "卸载完成"
            var text = "已移除 \(outcome.removedCount) 项。"
            if !outcome.kept.isEmpty { text += "\n已保留：\n" + outcome.kept.joined(separator: "\n") }
            detail.stringValue = text + "\n请注销并重新登录，清空输入法菜单中的残留项。"
            afterUninstall(outcome)
        case .failure(let error):
            running = false
            setBusy(false)
            uninstallButton.isEnabled = true
            status.stringValue = "卸载未完成"
            detail.stringValue = error.localizedDescription
        }
    }

    private func afterUninstall(_ outcome: UninstallOutcome) {
        uninstallButton.isHidden = true
        checkButton.isEnabled = false
        installButton.isEnabled = false
        relaunchButton.isHidden = true
        if !outcome.pendingSelfRemoval.isEmpty {
            _ = UninstallRunner.scheduleSelfRemoval(outcome.pendingSelfRemoval)
        }
        NSApp.terminate(nil)
    }

    @objc private func relaunchTapped() {
        guard !running, let applications = location?.applications else { return }
        let app = applications.appendingPathComponent(InstallTarget.updater.bundleName)
        guard FileManager.default.fileExists(atPath: app.path) else {
            return fail("找不到更新程序：\(app.path)")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["--ui"]
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                guard error == nil else {
                    self?.fail("重新打开失败：\(error!.localizedDescription)")
                    return
                }
                NSApp.terminate(nil)
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
