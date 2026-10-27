import AppKit
import Foundation
import LampyrisInstallCore

/// UI 层只负责文案与确认；删除/保留/自删除的语义全部在共享的 InstallCore 里（ADR-296）。
private enum UninstallEngine {
    static func run(mode: UninstallMode) throws -> UninstallOutcome {
        try UninstallerCore.run(
            mode: mode, paths: .production(),
            stopApps: { identifiers in stopApplications(identifiers) },
            switchToABCAndDisable: { helper in switchToABCAndDisable(helper: helper) })
    }

    private static func stopApplications(_ identifiers: [String]) {
        let running = identifiers.flatMap {
            NSRunningApplication.runningApplications(withBundleIdentifier: $0)
        }
        guard !running.isEmpty else { return }
        for application in running where !application.isTerminated {
            application.terminate()
        }
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && running.contains(where: { !$0.isTerminated }) {
            usleep(100_000)
        }
        for application in running where !application.isTerminated {
            application.forceTerminate()
        }
    }

    private static func switchToABCAndDisable(helper: URL) {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        for arguments in [["switch-abc"], ["disable", UninstallIdentifiers.host]] {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }
}

@MainActor
private final class UninstallerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let status = NSTextField(labelWithString: "选择卸载方式")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "卸载后请注销并重新登录，以清理输入法菜单中的残留项。")
    private let keepButton = NSButton(radioButtonWithTitle: "保留配置与词库", target: nil, action: nil)
    private let cleanButton = NSButton(radioButtonWithTitle: "彻底清理全部数据", target: nil, action: nil)
    private let uninstallButton = NSButton(title: "卸载", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var busy = false
    private var finished = false
    private var removeAll = false

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) · 构建 \(build)"
    }

    func show() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 330),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "卸载萤火虫"
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
        let version = NSTextField(labelWithString: "版本 \(versionText)")
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
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor

        keepButton.target = self
        keepButton.action = #selector(modeChanged(_:))
        keepButton.state = .on
        cleanButton.target = self
        cleanButton.action = #selector(modeChanged(_:))
        let choices = NSStackView(views: [keepButton, cleanButton])
        choices.orientation = .vertical
        choices.alignment = .leading
        choices.spacing = 8

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true

        uninstallButton.bezelStyle = .rounded
        uninstallButton.controlSize = .large
        uninstallButton.bezelColor = .controlAccentColor
        uninstallButton.keyEquivalent = "\r"
        uninstallButton.target = self
        uninstallButton.action = #selector(uninstallTapped)
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, spinner, cancelButton, uninstallButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [header, separator, status, detail, choices, buttons, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 540, height: 302)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            choices.widthAnchor.constraint(equalTo: detail.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: detail.widthAnchor),
            footer.widthAnchor.constraint(equalTo: detail.widthAnchor),
        ])
        panel.setContentSize(NSSize(width: 540, height: 302))
        stack.layoutSubtreeIfNeeded()
        panel.center()

        updateModeDetail()
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func modeChanged(_ sender: NSButton) {
        removeAll = sender == cleanButton
        keepButton.state = removeAll ? .off : .on
        cleanButton.state = removeAll ? .on : .off
        updateModeDetail()
    }

    private func updateModeDetail() {
        if removeAll {
            detail.stringValue = "将移除应用、更新程序、配置、个人词库、更新备份、缓存、偏好设置与诊断日志；删除后无法恢复。"
            uninstallButton.title = "彻底清理"
        } else {
            detail.stringValue = "将移除应用、更新程序、更新备份、缓存、偏好设置与诊断日志；仅保留 config.toml 与 user-dictionary.tsv，重新安装后可继续使用。"
            uninstallButton.title = "卸载"
        }
    }

    private func finish() {
        window?.close()
        NSApp.terminate(nil)
    }

    @objc private func cancelTapped() {
        guard !busy else { return }
        finish()
    }

    @objc private func uninstallTapped() {
        if finished {
            finish()
            return
        }
        let mode: UninstallMode = removeAll ? .removeAll : .keepData
        if removeAll {
            let alert = NSAlert()
            alert.messageText = "彻底清理全部数据？"
            alert.informativeText = "配置、个人词库、更新备份与缓存都会被删除，且无法恢复。"
            alert.addButton(withTitle: "全部删除")
            alert.addButton(withTitle: "取消")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        start(mode: mode)
    }

    private func start(mode: UninstallMode) {
        busy = true
        uninstallButton.isEnabled = false
        cancelButton.isEnabled = false
        keepButton.isEnabled = false
        cleanButton.isEnabled = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        status.stringValue = "正在卸载…"
        Task.detached {
            let result: Result<UninstallOutcome, Error>
            do {
                result = .success(try UninstallEngine.run(mode: mode))
            } catch {
                result = .failure(error)
            }
            await MainActor.run { [weak self] in
                self?.complete(result, mode: mode)
            }
        }
    }

    private func complete(_ result: Result<UninstallOutcome, Error>, mode: UninstallMode) {
        busy = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        switch result {
        case .success(let outcome):
            finished = true
            status.stringValue = mode == .removeAll ? "已彻底清理" : "卸载完成"
            var detailText = "已移除 \(outcome.removedCount) 项应用、更新与缓存内容。"
            if !outcome.kept.isEmpty {
                detailText += "\n已保留：\n" + outcome.kept.joined(separator: "\n")
            }
            detailText += "\n请注销并重新登录，清空输入法菜单中的残留项。"
            detail.stringValue = detailText
            uninstallButton.title = "完成"
            uninstallButton.isEnabled = true
            cancelButton.isHidden = true
            keepButton.isHidden = true
            cleanButton.isHidden = true
            footer.stringValue = "如需重新安装，请打开 DMG 双击「安装萤火虫」。"
        case .failure(let error):
            uninstallButton.isEnabled = true
            cancelButton.isEnabled = true
            keepButton.isEnabled = true
            cleanButton.isEnabled = true
            status.stringValue = "清理未完成"
            detail.stringValue = error.localizedDescription
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if !busy { NSApp.terminate(nil) }
    }
}

@main
private struct LampyrisUninstallerMain {
    @MainActor private static let delegate = AppDelegate()

    @MainActor
    static func main() {
        let application = NSApplication.shared
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = UninstallerWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
        controller.show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
