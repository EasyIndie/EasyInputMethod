// 用户反馈信息（ADR-071 / ADR-074 / ADR-078）：**完全本地**——「关于」窗口展示诊断信息
// 与反馈渠道；用户显式点击时可交给默认浏览器打开，输入法自身不联网、不发送任何数据。
// 诊断信息不含输入内容/词库/配置。
//
// 不探测渠道可用性，打开失败时在信息窗口保留可复制地址（ADR-102）。
//
// 见 `docs/隐私与安全.md` §1/§6、`SECURITY.md`。

import Cocoa

enum FeedbackUI {
    /// 公开反馈渠道（静态链接，不携带任何参数）。
    static let issuesURL = URL(
        string: "https://github.com/EasyIndie/EasyInputMethod/issues/new")!
    /// 敏感漏洞的私下渠道。
    static let securityURL = URL(
        string: "https://github.com/EasyIndie/EasyInputMethod/security/advisories/new")!

    /// 诊断文本：仅版本/构建/源码提交/系统/架构，绝不含输入内容或用户数据。
    static func diagnostics(bundle: Bundle = .main) -> String {
        let info = bundle.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var commit = "未知"
        if let url = bundle.resourceURL?.appendingPathComponent("SOURCE-COMMIT"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            commit = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #if arch(arm64)
        let arch = "arm64"
        #elseif arch(x86_64)
        let arch = "x86_64"
        #else
        let arch = "unknown"
        #endif
        return """
        萤火虫 Lampyris \(version)（构建 \(build)）
        源码提交：\(commit)
        系统：\(ProcessInfo.processInfo.operatingSystemVersionString)
        架构：\(arch)
        """
    }
}
