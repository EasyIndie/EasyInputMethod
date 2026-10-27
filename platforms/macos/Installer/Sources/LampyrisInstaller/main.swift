import AppKit
import Foundation
import LampyrisInstallCore

private let appIdentifier = "cn.jokerhub.inputmethod.Lampyris"
private let updaterIdentifier = "cn.jokerhub.Lampyris.WebsiteUpdateCheck"
private let updaterBundleName = "LampyrisUpdateCheck.app"
/// ADR-294 之前的手工改名：只在清理时识别，不再作为查找判据。
private let legacyUpdaterBundleName = "Lampyris Update.app"

private struct Payload: Sendable {
    let url: URL
    let updaterURL: URL
    let version: String
    let build: String
    let updaterVersion: String
    var displayVersion: String { "\(version) · 构建 \(build)" }
}

private struct InstallOutcome: Sendable {
    let backup: String?
    let updaterBackup: [String]
    let removedLegacyUpdater: String?
    let registered: Bool
}

private enum InstallFailure: LocalizedError {
    case missingPayload
    case invalidPayload(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingPayload:
            return "安装包内缺少 Lampyris.app 或 LampyrisUpdateCheck.app。请从完整 DMG 中运行本安装器。"
        case .invalidPayload(let reason): return reason
        case .installFailed(let reason): return reason
        }
    }
}

private enum InstallEngine {
    struct AppInfo {
        let version: String
        let build: String
    }

    static func stopHosts() {
        stopApplications(withBundleIdentifier: appIdentifier)
    }

    private static func stopApplications(withBundleIdentifier identifier: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
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

    static func readPayload(at url: URL, updaterURL: URL) throws -> Payload {
        let app = try readInfo(app: url, identifier: appIdentifier, executable: "Contents/MacOS/Lampyris")
        let updater = try readInfo(app: updaterURL, identifier: updaterIdentifier,
                                   executable: "Contents/MacOS/LampyrisUpdateCheck")
        return Payload(url: url, updaterURL: updaterURL, version: app.version, build: app.build,
                       updaterVersion: updater.version)
    }

    /// 只读取展示用信息；签名/公证/Gatekeeper 的完整校验由共享的 InstallCore 执行（ADR-295）。
    static func readInfo(app: URL, identifier: String, executable: String) throws -> AppInfo {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: app.path), !isSymlink(app) else {
            throw InstallFailure.missingPayload
        }
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let binary = app.appendingPathComponent(executable)
        guard let data = try? Data(contentsOf: plist),
            let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            info["CFBundleIdentifier"] as? String == identifier,
            let version = info["CFBundleShortVersionString"] as? String,
            let build = info["CFBundleVersion"] as? String,
            fileManager.isExecutableFile(atPath: binary.path),
            !isSymlink(binary)
        else {
            throw InstallFailure.invalidPayload("\(app.lastPathComponent) 不完整或身份不符。")
        }
        return AppInfo(version: version, build: build)
    }

    /// 先装更新程序、再装输入法；输入法失败时把更新程序一并恢复，避免半新半旧。
    static func install(payload: Payload, destination: URL, support: URL, home: URL) throws
        -> InstallOutcome
    {
        let fileManager = FileManager.default
        let applications = home.appendingPathComponent("Applications")
        guard !isSymlink(applications) else {
            throw InstallFailure.installFailed("~/Applications 是符号链接，已停止安装更新程序。")
        }
        try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
        let backupRoot = support.appendingPathComponent("updates/dmg-backup-\(timestamp())")
        var removedLegacy: String?
        let legacy = applications.appendingPathComponent(legacyUpdaterBundleName)
        if fileManager.fileExists(atPath: legacy.path),
            Bundle(url: legacy)?.bundleIdentifier == updaterIdentifier
        {
            do {
                try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
                let target = backupRoot.appendingPathComponent(legacyUpdaterBundleName)
                try fileManager.moveItem(at: legacy, to: target)
                removedLegacy = target.path
            } catch {
                throw InstallFailure.installFailed("迁移旧版更新程序失败：\(error.localizedDescription)")
            }
        }
        let updaterDestination = applications.appendingPathComponent(updaterBundleName)
        let updaterBackup: String?
        do {
            updaterBackup = try UpdateInstaller.replaceBundle(
                candidate: payload.updaterURL, destination: updaterDestination,
                backupRoot: backupRoot,
                environment: DefaultInstallEnvironment.make(target: .updater), target: .updater)
        } catch {
            throw InstallFailure.installFailed("安装更新程序失败：\(error.localizedDescription)")
        }
        let backup: String?
        do {
            backup = try UpdateInstaller.replaceBundle(
                candidate: payload.url, destination: destination, backupRoot: backupRoot,
                environment: DefaultInstallEnvironment.make(target: .production), target: .production)
        } catch {
            restoreUpdater(destination: updaterDestination, backup: updaterBackup)
            throw InstallFailure.installFailed("\(error.localizedDescription)")
        }
        let registered = registerInputSource(at: destination)
        return InstallOutcome(backup: backup, updaterBackup: updaterBackup.map { [$0] } ?? [],
                              removedLegacyUpdater: removedLegacy, registered: registered)
    }

    private static func restoreUpdater(destination: URL, backup: String?) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard let backup else { return }
        try? fileManager.moveItem(atPath: backup, toPath: destination.path)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    }

    /// 注册/启用后回读真实状态（macOS 13 上调用返回值不可信，报告201/207）。
    private static func registerInputSource(at app: URL) -> Bool {
        let helper = app.appendingPathComponent("Contents/Helpers/LampyrisTIS")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return false }
        _ = runs(helper, ["register", app.path])
        _ = runs(helper, ["enable", appIdentifier])
        let status = output(helper, ["status", appIdentifier])
        for line in status.split(separator: "\n") where line.hasPrefix("enabled ") {
            let listed = line.dropFirst("enabled ".count)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            return listed.contains(appIdentifier)
        }
        return false
    }

    private static func runs(_ tool: URL, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private static func output(_ tool: URL, _ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
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
    private var updaterPayloadURL: URL { bundleDirectory.appendingPathComponent(updaterBundleName) }

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
            let payload = try InstallEngine.readPayload(at: payloadURL, updaterURL: updaterPayloadURL)
            self.payload = payload
            version.stringValue = "版本 \(payload.displayVersion)"
            detail.stringValue = "将安装输入法与更新程序到当前用户（~/Library/Input Methods、~/Applications）。\n保留配置与词库，旧版本会自动备份。"
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
        detail.stringValue = "停止旧宿主并写入输入法目录与 ~/Applications。"
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Input Methods/Lampyris.app")
        let support = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Lampyris")
        let home = FileManager.default.homeDirectoryForCurrentUser
        InstallEngine.stopHosts()
        Task.detached {
            let result: Result<InstallOutcome, InstallFailure>
            do {
                result = .success(try InstallEngine.install(
                    payload: payload, destination: destination, support: support, home: home))
            } catch let error as InstallFailure {
                result = .failure(error)
            } catch {
                result = .failure(.installFailed(error.localizedDescription))
            }
            await MainActor.run { [weak self] in
                self?.complete(result, payload: payload)
            }
        }
    }

    private func complete(_ result: Result<InstallOutcome, InstallFailure>, payload: Payload) {
        busy = false
        spinner.stopAnimation(nil)
        spinner.isHidden = true
        switch result {
        case .success(let outcome):
            installed = true
            status.stringValue = "安装完成"
            var lines = ["已安装 \(payload.displayVersion)。",
                         "更新程序 \(payload.updaterVersion)：~/Applications/\(updaterBundleName)"]
            if let removed = outcome.removedLegacyUpdater {
                lines.append("旧位置已迁移：\(removed)")
            }
            if outcome.backup != nil { lines.append("旧版本已备份到 Application Support/Lampyris/updates。") }
            detail.stringValue = lines.joined(separator: "\n")
            installButton.title = "完成"
            installButton.isEnabled = true
            cancelButton.isHidden = true
            footer.stringValue = outcome.registered
                ? "已注册输入源：用 ⌃Space 或输入法菜单选中「萤火虫」即可。"
                : "请在系统设置 → 键盘 → 文字输入 → ＋ 添加「萤火虫」；可能需重新登录一次。"
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
