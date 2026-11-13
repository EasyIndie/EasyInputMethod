import Cocoa

/// 首次启用时的上手提示（ADR-343）。
///
/// 只在正式宿主、非验收私有根、且尚未看过时出现一次；标记文件与练习进度同类，不是配置，
/// 也不参与任何排序或学习。写入标记失败时宁可不弹，避免每次激活都打扰。
enum Onboarding {
    static let markerName = "onboarding-done"
    private static let productionIdentifier = "cn.jokerhub.inputmethod.Lampyris"
    private static var presented = false

    static func presentIfNeeded() {
        guard !presented else { return }
        presented = true
        guard Bundle.main.bundleIdentifier == productionIdentifier else { return }
        guard ProcessInfo.processInfo.environment[ImePaths.supportDirectoryEnvironmentKey] == nil else {
            return
        }
        guard let directory = ImePaths.supportDirectory() else { return }
        let marker = directory.appendingPathComponent(markerName)
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("1\n".utf8).write(to: marker, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: marker.path)
        } catch {
            return
        }
        show()
    }

    private static func show() {
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = "欢迎使用萤火虫输入法"
        alert.informativeText = [
            "默认混合输入：五笔优先，想不起编码时用拼音兜底。",
            "\(hotkey("hotkey.toggle_mode")) 切换模式 · \(hotkey("hotkey.open_settings")) 设置"
                + " · \(hotkey("hotkey.open_practice")) 练习 · \(hotkey("hotkey.toggle_wubi_learning")) 学习区",
            "这些快捷键都可以在设置里修改；本提示只出现一次。",
        ].joined(separator: "\n")
        alert.addButton(withTitle: "开始使用")
        alert.runModal()
    }

    /// 按 `config.toml` 的写法显示快捷键，例如 `⌥M`、`⇧Space`。
    private static func hotkey(_ key: String) -> String {
        let binding = ImeConfig.hotkey(key)
        guard binding.kind == 2 else { return "—" }
        var text = ""
        if binding.modifiers.contains(.control) { text += "⌃" }
        if binding.modifiers.contains(.option) { text += "⌥" }
        if binding.modifiers.contains(.shift) { text += "⇧" }
        if binding.modifiers.contains(.command) { text += "⌘" }
        return text + binding.equivalent.uppercased()
    }
}
