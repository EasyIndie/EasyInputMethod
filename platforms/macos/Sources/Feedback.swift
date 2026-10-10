// 用户反馈入口（ADR-071 / ADR-074）：**完全本地**——面板只展示诊断信息与反馈渠道链接文本，
// 由用户自行复制并在浏览器中提交；输入法自身**不打开浏览器、不联网、不发送任何数据**。
// 诊断信息不含输入内容/词库/配置。
//
// 不调用 `NSWorkspace.open` 等任何外部打开 API：既不会因网络不可达而卡死，也无需按可用性
// 隐藏入口（关闭代理、GitHub 打不开时，复制到本地仍可用）。
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

    /// 可整段复制的反馈正文：诊断信息 + 反馈渠道链接（纯文本，用户自行提交）。
    static func feedbackText(bundle: Bundle = .main) -> String {
        """
        \(diagnostics(bundle: bundle))

        反馈渠道（请自行在浏览器打开；本输入法不联网、不代发）：
        - 问题 / 建议：\(issuesURL.absoluteString)
        - 敏感漏洞：\(securityURL.absoluteString)
        """
    }

    static func show() {
        let alert = NSAlert()
        alert.messageText = "反馈问题 / 改进建议"
        alert.informativeText = """
            萤火虫不联网、不上报：本窗口不会发送或打开任何内容。
            请点「复制反馈信息」，自行到 GitHub Issues 粘贴提交；下面的链接也可手动选中复制。

            内容不含你的输入内容、词库或配置。
            """

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 470, height: 170))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = feedbackText()
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll

        alert.addButton(withTitle: "复制反馈信息")
        alert.addButton(withTitle: "关闭")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // 只写入剪贴板；不打开浏览器、不发起任何网络连接。
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            _ = pasteboard.setString(feedbackText(), forType: .string)
            let done = NSAlert()
            done.messageText = "反馈信息已复制"
            done.informativeText = "可粘贴到 GitHub Issue；敏感漏洞请改走私密安全公告。"
            done.runModal()
        default:
            break
        }
    }
}
