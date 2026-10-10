// 用户反馈入口（ADR-071）：不自动外发任何数据；仅当用户点击时用系统浏览器打开
// 公开的 GitHub Issues 页面。诊断信息不含输入内容/词库/配置，由用户自行决定是否复制。
//
// 健壮性（ADR-073）：
//   1) 打开链接一律走**异步** API，绝不阻塞主线程 / 菜单事件循环；
//   2) 仅在“系统存在可打开该链接的应用”时才显示菜单入口，避免死入口。
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

    /// GitHub Issues 反馈在本机是否可用：**只做本地判断**——系统是否存在能打开该 https
    /// 链接的应用（默认浏览器）。查询 LaunchServices 本地数据库，不联网、不探测 GitHub 可达性
    ///（铁律 1 禁止 App 发起任何网络请求）。因此“代理关闭导致 GitHub 打不开”这类**网络层**
    /// 不可达无法在此识别；不可用时由菜单隐藏入口，避免点击无反应。
    /// 语义集中在此处（唯一真值），将来若要改判据只改这里。
    static let isAvailable: Bool = NSWorkspace.shared.urlForApplication(toOpen: issuesURL) != nil

    /// 统一的外部链接打开入口：交给系统**异步**打开，绝不阻塞调用线程。
    /// 禁止使用同步的 `NSWorkspace.open(url)`——它在浏览器/LaunchServices 异常时会卡死主线程，
    /// 导致整个输入法菜单失去响应（见 ADR-073）。
    static func openExternally(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            if let error {
                NSLog("萤火虫：打开链接失败（\(url.absoluteString)）：\(error.localizedDescription)")
            }
        }
    }

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
            // 用户主动打开浏览器；App 自身不发起任何网络连接（异步、不阻塞主线程）。
            openExternally(issuesURL)
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
