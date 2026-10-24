import AppKit
import Foundation

private let hostIdentifier = "cn.jokerhub.inputmethod.Lampyris"
private let updaterIdentifier = "cn.jokerhub.Lampyris.WebsiteUpdateCheck"
private let installerIdentifier = "cn.jokerhub.Lampyris.Installer"
private let uninstallerIdentifier = "cn.jokerhub.Lampyris.Uninstaller"

private enum UninstallMode: Sendable {
    case keepData
    case removeAll
}

private enum UninstallError: LocalizedError {
    case invalidApp
    case residual([String])

    var errorDescription: String? {
        switch self {
        case .invalidApp: return "当前安装不是萤火虫输入法，已停止。"
        case .residual(let paths): return "仍有文件未能删除：\n" + paths.joined(separator: "\n")
        }
    }
}

private struct UninstallOutcome: Sendable {
    let kept: [String]
    let removedCount: Int
}

private enum UninstallEngine {
    static func run(mode: UninstallMode) throws -> UninstallOutcome {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let app = home.appendingPathComponent("Library/Input Methods/Lampyris.app")
        let support = home.appendingPathComponent("Library/Application Support/Lampyris")
        let updater = home.appendingPathComponent("Applications/Lampyris Update.app")
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: app.path), !isProductionApp(app) {
            throw UninstallError.invalidApp
        }
        if fileManager.fileExists(atPath: app.path) {
            stopHosts([hostIdentifier, updaterIdentifier])
            switchToABCAndDisable(helper: app.appendingPathComponent("Contents/Helpers/LampyrisTIS"))
            stopHosts([hostIdentifier, updaterIdentifier])
        } else {
            stopHosts([hostIdentifier, updaterIdentifier])
        }

        var failures: [String] = []
        var removed = 0
        func remove(_ url: URL) {
            guard fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.removeItem(at: url)
                removed += 1
            } catch {
                failures.append(url.path)
            }
        }

        let identifiers = [hostIdentifier, updaterIdentifier, installerIdentifier]
        var targets: [URL] = [
            app,
            updater,
            home.appendingPathComponent("Library/Application Support/Lampyris-install-backups"),
            home.appendingPathComponent("Library/Application Scripts/\(hostIdentifier)"),
        ]
        for identifier in identifiers {
            targets.append(home.appendingPathComponent("Library/Caches/\(identifier)"))
            targets.append(home.appendingPathComponent("Library/Preferences/\(identifier).plist"))
            targets.append(home.appendingPathComponent("Library/Saved Application State/\(identifier).savedState"))
            targets.append(home.appendingPathComponent("Library/Containers/\(identifier)"))
            targets.append(home.appendingPathComponent("Library/HTTPStorages/\(identifier)"))
        }
        targets.append(home.appendingPathComponent("Library/Preferences/\(uninstallerIdentifier).plist"))
        for target in targets { remove(target) }
        removeDiagnostics(home: home, remove: remove)
        removeTemporaryDiagnostics(remove: remove)

        var kept: [String] = []
        if mode == .removeAll {
            remove(support)
        } else {
            let userFiles = ["config.toml", "user-dictionary.tsv"]
            if let children = try? fileManager.contentsOfDirectory(
                at: support, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            {
                for child in children where !userFiles.contains(child.lastPathComponent) {
                    remove(child)
                }
            }
            for name in userFiles
            where fileManager.fileExists(atPath: support.appendingPathComponent(name).path) {
                kept.append(support.appendingPathComponent(name).path)
            }
            if let children = try? fileManager.contentsOfDirectory(atPath: support.path), children.isEmpty {
                try? fileManager.removeItem(at: support)
            }
        }

        if !failures.isEmpty {
            throw UninstallError.residual(failures)
        }
        if mode == .removeAll {
            let leftovers = targets.filter { fileManager.fileExists(atPath: $0.path) }
                + [support].filter { fileManager.fileExists(atPath: $0.path) }
            if !leftovers.isEmpty {
                throw UninstallError.residual(leftovers.map(\.path))
            }
        }
        return UninstallOutcome(kept: kept, removedCount: removed)
    }

    private static func stopHosts(_ identifiers: [String]) {
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
        for arguments in [["switch-abc"], ["disable", hostIdentifier]] {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func removeDiagnostics(home: URL, remove: (URL) -> Void) {
        let prefixes = ["Lampyris-", "LampyrisUpdateCheck-", "LampyrisInstaller-", "LampyrisUninstaller-"]
        let crashPrefixes = ["Lampyris_", "LampyrisUpdateCheck_", "LampyrisInstaller_", "LampyrisUninstaller_"]
        for (directory, names) in [
            (home.appendingPathComponent("Library/Logs/DiagnosticReports"), prefixes),
            (home.appendingPathComponent("Library/Application Support/CrashReporter"), crashPrefixes),
        ] {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for child in children where names.contains(where: { child.lastPathComponent.hasPrefix($0) }) {
                remove(child)
            }
        }
    }

    private static func removeTemporaryDiagnostics(remove: (URL) -> Void) {
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lampyris-hud-diag.log")
        remove(temporary)
    }

    private static func isProductionApp(_ app: URL) -> Bool {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return false }
        return info["CFBundleIdentifier"] as? String == hostIdentifier
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
        let version = NSTextField(labelWithString: "卸载工具")
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
