// 用户反馈入口（ADR-071）：不自动外发任何数据；仅当用户点击时用系统浏览器打开
// 公开的 GitHub Issues 页面。诊断信息不含输入内容/词库/配置，由用户自行决定是否复制。
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

    static func show() {
        let alert = NSAlert()
        alert.messageText = "反馈问题 / 改进建议"
        alert.informativeText = """
            欢迎到项目 GitHub Issues 报告问题或提出建议。

            萤火虫不联网、不上报：本窗口不会自动发送任何内容，是否分享由你决定。下面的诊断信息不含你的输入内容、词库或配置。
            """

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 470, height: 130))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = diagnostics()
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "打开 GitHub Issues")
        alert.addButton(withTitle: "复制诊断信息")
        alert.addButton(withTitle: "关闭")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // 用户主动打开浏览器；App 自身不发起任何网络连接。
            _ = NSWorkspace.shared.open(issuesURL)
        case .alertSecondButtonReturn:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            _ = pasteboard.setString(diagnostics(), forType: .string)
            let done = NSAlert()
            done.messageText = "诊断信息已复制"
            done.informativeText =
                "可粘贴到 GitHub Issue。\n敏感漏洞请改走私密安全公告：\(securityURL.absoluteString)"
            done.runModal()
        default:
            break
        }
    }
}
