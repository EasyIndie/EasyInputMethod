import AppKit
import Foundation
import Security

private let appIdentifier = "cn.jokerhub.inputmethod.Lampyris"

private struct Payload: Sendable {
    let url: URL
    let version: String
    let build: String
    var displayVersion: String { "\(version) · 构建 \(build)" }
}

private enum InstallError: LocalizedError {
    case missingPayload
    case invalidPayload(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPayload: return "安装包内缺少 Lampyris.app。请从 DMG 中运行本安装器。"
        case .invalidPayload(let reason): return reason
        case .installFailed(let reason): return reason
        }
    }
}

private enum InstallEngine {
    static func stopHosts() {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: appIdentifier)
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

    static func readPayload(at url: URL) throws -> Payload {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path), !isSymlink(url) else {
            throw InstallError.missingPayload
        }
        let plist = url.appendingPathComponent("Contents/Info.plist")
        let executable = url.appendingPathComponent("Contents/MacOS/Lampyris")
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            info["CFBundleIdentifier"] as? String == appIdentifier,
            let version = info["CFBundleShortVersionString"] as? String,
            let build = info["CFBundleVersion"] as? String,
            fileManager.isExecutableFile(atPath: executable.path),
            !isSymlink(executable)
        else {
            throw InstallError.invalidPayload("安装包内的 Lampyris.app 不完整或身份不符。")
        }
        guard signatureIsValid(url) else {
            throw InstallError.invalidPayload("安装包内的 Lampyris.app 签名无效，已停止安装。")
        }
        return Payload(url: url, version: version, build: build)
    }

    static func install(payload: Payload, destination: URL, support: URL) throws -> String? {
        let fileManager = FileManager.default
        let domain = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: domain, withIntermediateDirectories: true)
        guard !isSymlink(domain) else {
            throw InstallError.installFailed("输入法目录是符号链接，已停止安装。")
        }
        let staging = domain.appendingPathComponent(".lampyris-install-\(UUID().uuidString)")
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent("Lampyris.app")
        try fileManager.copyItem(at: payload.url, to: staged)
        _ = try readPayload(at: staged)

        var backup: URL?
        if fileManager.fileExists(atPath: destination.path) {
            guard !isSymlink(destination) else {
                throw InstallError.installFailed("现有输入法是符号链接，已停止安装。")
            }
            let stamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupRoot = support.appendingPathComponent("updates/dmg-backup-\(stamp)")
            do {
                try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
                let target = backupRoot.appendingPathComponent("Lampyris.app")
                try fileManager.moveItem(at: destination, to: target)
                backup = target
            } catch {
                throw InstallError.installFailed("备份现有版本失败：\(error.localizedDescription)")
            }
        }

        do {
            try fileManager.moveItem(at: staged, to: destination)
        } catch {
            if let backup {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw InstallError.installFailed("写入输入法目录失败：\(error.localizedDescription)")
        }

        do {
            _ = try readPayload(at: destination)
        } catch {
            try? fileManager.removeItem(at: destination)
            if let backup {
                try? fileManager.moveItem(at: backup, to: destination)
            }
            throw InstallError.installFailed("安装后校验失败，已回滚：\(error.localizedDescription)")
        }

        registerInputSource(at: destination)
        return backup?.path
    }

    /// Best effort: registration/enabling works without a login for the bundled helper.
    private static func registerInputSource(at app: URL) {
        let helper = app.appendingPathComponent("Contents/Helpers/LampyrisTIS")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return }
        for arguments in [["register", app.path], ["enable", appIdentifier]] {
            let process = Process()
            process.executableURL = helper
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func signatureIsValid(_ app: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            return false
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess
    }
}

@MainActor
private final class InstallerWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let status = NSTextField(labelWithString: "准备安装")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let footer = NSTextField(labelWithString: "安装后按 ⌃Space，或在输入法菜单中选择「萤火虫」。")
    private let installButton = NSButton(title: "安装", target: nil, action: nil)
    private let cancelButton = NSButton(title: "取消", target: nil, action: nil)
    private let spinner = NSProgressIndicator()
    private var payload: Payload?
    private var busy = false
    private var installed = false

    private var bundleDirectory: URL { Bundle.main.bundleURL.deletingLastPathComponent() }
    private var payloadURL: URL { bundleDirectory.appendingPathComponent("Lampyris.app") }

    func show() {
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "安装萤火虫"
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
        let version = NSTextField(labelWithString: "正在读取安装包…")
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
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .tertiaryLabelColor

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isHidden = true

        installButton.bezelStyle = .rounded
        installButton.controlSize = .large
        installButton.bezelColor = .controlAccentColor
        installButton.keyEquivalent = "\r"
        installButton.target = self
        installButton.action = #selector(installTapped)
        installButton.isEnabled = false
        cancelButton.bezelStyle = .rounded
        cancelButton.controlSize = .large
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, spinner, cancelButton, installButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 10

        let stack = NSStackView(views: [header, separator, status, detail, buttons, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = true
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 286)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            detail.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            buttons.widthAnchor.constraint(equalTo: detail.widthAnchor),
            footer.widthAnchor.constraint(equalTo: detail.widthAnchor),
        ])
        panel.setContentSize(NSSize(width: 520, height: 286))
        stack.layoutSubtreeIfNeeded()
        panel.center()

        do {
            let payload = try InstallEngine.readPayload(at: payloadURL)
            self.payload = payload
            version.stringValue = "版本 \(payload.displayVersion)"
            detail.stringValue = "将安装到当前用户（~/Library/Input Methods）。保留配置与词库，旧版本会自动备份。"
            installButton.isEnabled = true
        } catch {
            status.stringValue = "无法安装"
            detail.stringValue = error.localizedDescription
            version.stringValue = "安装包不可用"
        }

        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish() {
        window?.close()
        NSApp.terminate(nil)
    }

    @objc private func cancelTapped() {
        guard !busy else { return }
        finish()
    }

    @objc private func installTapped() {
        if installed {
            finish()
            return
        }
        guard let payload, !busy else { return }
        busy = true
        installButton.isEnabled = false
        cancelButton.isEnabled = false
        spinner.isHidden = false
        spinner.startAnimation(nil)
        status.stringValue = "正在安装…"
        detail.stringValue = "停止旧宿主并写入输入法目录。"
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/Lampyris.app")
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lampyris")
        InstallEngine.stopHosts()
        Task.detached {
            let result: Result<String?, InstallError>
            do {
                result = .success(try InstallEngine.install(
                    payload: payload, destination: destination, support: support))
            } catch let error as InstallError {
                result = .failure(error)
            } catch {
                result = .failure(.installFailed(error.localizedDescription))
            }
            await MainActor.run { [weak self] in
                self?.complete(result, payload: payload)
            }
        }
    }

    private func complete(_ result: Result<String?, InstallError>, payload: Payload) {
        busy = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        switch result {
        case .success(let backup):
            installed = true
            status.stringValue = "安装完成"
            detail.stringValue = "已安装 \(payload.displayVersion)。"
                + (backup.map { "旧版本备份：\($0)" } ?? "")
            installButton.title = "完成"
            installButton.isEnabled = true
            cancelButton.isHidden = true
            footer.stringValue = "首次使用请在输入法菜单中选择「萤火虫」；可能需要重新登录一次。"
        case .failure(let error):
            installButton.isEnabled = true
            cancelButton.isEnabled = true
            status.stringValue = "安装失败"
            detail.stringValue = error.localizedDescription
        }
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if !busy { NSApp.terminate(nil) }
    }
}

@main
private struct LampyrisInstallerMain {
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
    private let controller = InstallerWindowController()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(named: "AppIcon") { NSApp.applicationIconImage = icon }
        controller.show()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
