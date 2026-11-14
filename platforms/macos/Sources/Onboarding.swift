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
        OnboardingWindow.shared.show(firstRun: true)
    }
}
