import Foundation
import LampyrisInstallCore

/// 「当前版本」显示的唯一来源：**已安装宿主** bundle 的 Info.plist。
///
/// 用 `Bundle.main` 会显示更新程序自己的版本：老更新程序把新宿主装好之后标题仍是旧的，
/// 用户看到「当前版本 0.1.14 · 构建 23」而状态行写着「已安装构建 24」，容易判定成「没更新」
/// （报告 214）。所以窗口启动时与安装成功后都从这里重新读。
enum InstalledVersion {
    static func text(bundleAt url: URL?) -> String {
        guard let url, let plist = info(at: url),
              let version = plist["CFBundleShortVersionString"] as? String,
              let build = plist["CFBundleVersion"] as? String,
              !version.isEmpty, !build.isEmpty
        else { return "未知" }
        return "\(version) · 构建 \(build)"
    }

    /// 已安装宿主的版本描述；location 解析失败或宿主不存在时返回「未知」。
    static func installed(_ location: InstallLocation?) -> String {
        guard let location else { return "未知" }
        return text(bundleAt: location.domain.appendingPathComponent(location.target.bundleName))
    }

    static func info(at url: URL) -> [String: Any]? {
        let plist = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else { return nil }
        // swiftlint:disable:next force_try - 解析失败返回 nil，不抛出到 UI 层
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
