// 菜单「版本信息」窗口（ADR-077/078/079/080）：只读诊断文本 + 「复制信息」/跳转按钮。
//
// 与设置面板一致：不联网。跳转按钮仅在用户**显式点击**时用系统默认程序打开对应页面
// （异步打开，避免阻塞主线程，ADR-073）；App 自身不建立连接、不上报任何数据。

import Cocoa

/// 信息窗口里的一个跳转按钮（标题 + 目标 URL）。
struct InfoLink {
    let title: String
    let url: URL
}

/// 单例信息窗口：换标题与正文复用同一个面板，避免多个窗口堆积。
final class InfoWindow: NSObject {
    private static let shared = InfoWindow()
    private var panel: NSPanel?
    private var currentText = ""
    private var links: [InfoLink] = []
    private let status = NSTextField(wrappingLabelWithString: "")
    private let fallbackAddress = NSTextField(wrappingLabelWithString: "")
    private lazy var copyAddressButton = NSButton(title: "复制地址", target: self, action: #selector(copyAddress))
    private var presentationID = UUID()

    static func show(title: String, text: String, allowsCopy: Bool, links: [InfoLink] = []) {
        shared.present(title: title, text: text, allowsCopy: allowsCopy, links: links)
    }

    private func present(title: String, text: String, allowsCopy: Bool, links: [InfoLink]) {
        currentText = text
        self.links = links
        presentationID = UUID()
        status.stringValue = ""
        fallbackAddress.stringValue = ""
        fallbackAddress.isSelectable = true
        fallbackAddress.isHidden = true
        copyAddressButton.isHidden = true
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.title = title
        ImeAppearance.applyTheme(to: panel)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        var buttons: [NSView] = []
        if allowsCopy {
            buttons.append(NSButton(title: "复制信息", target: self, action: #selector(copyText)))
        }
        for (index, link) in links.enumerated() {
            let button = NSButton(title: link.title, target: self, action: #selector(openLink(_:)))
            button.tag = index
            buttons.append(button)
        }

        var views: [NSView] = [scroll]
        if !buttons.isEmpty {
            let row = NSStackView(views: buttons)
            row.orientation = .horizontal
            row.spacing = 10
            views.append(row)
        }
        views.append(status)
        views.append(fallbackAddress)
        views.append(copyAddressButton)
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            status.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
            fallbackAddress.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func copyText() {
        reportCopy(Self.copy(currentText, to: .general))
    }

    static func copy(_ text: String, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private func reportCopy(_ success: Bool) {
        status.stringValue = success ? "已复制" : "复制失败，请选中文字手动复制。"
        status.textColor = success ? ImeAppearance.secondaryText : ImeAppearance.errorText
    }

    @objc private func copyAddress() { reportCopy(Self.copy(fallbackAddress.stringValue, to: .general)) }

    private func finishOpen(_ url: URL, succeeded: Bool, presentation: UUID) {
        guard presentation == presentationID else { return }
        status.stringValue = succeeded ? "已交给默认浏览器打开。" : "打开失败，请复制地址到浏览器。"
        status.textColor = succeeded ? ImeAppearance.secondaryText : ImeAppearance.errorText
        fallbackAddress.stringValue = succeeded ? "" : url.absoluteString
        fallbackAddress.isHidden = succeeded
        copyAddressButton.isHidden = succeeded
    }

    static func testOpenResult(_ url: URL, succeeded: Bool) -> (String, String, Bool) {
        let window = InfoWindow()
        window.finishOpen(url, succeeded: succeeded, presentation: window.presentationID)
        return (window.status.stringValue, window.fallbackAddress.stringValue, !window.copyAddressButton.isHidden)
    }

    /// 用户显式点击跳转按钮才打开对应页面；异步打开，不阻塞主线程（ADR-073）。
    @objc private func openLink(_ sender: NSButton) {
        guard links.indices.contains(sender.tag) else { return }
        let url = links[sender.tag].url
        let identity = presentationID
        status.stringValue = "正在打开…"
        NSWorkspace.shared.open(
            url, configuration: NSWorkspace.OpenConfiguration()
        ) { [weak self] application, error in
            DispatchQueue.main.async {
                self?.finishOpen(url, succeeded: application != nil && error == nil, presentation: identity)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        ImeAppearance.applyTheme(to: panel)
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in
            if key == "appearance.theme", let panel = self?.panel { ImeAppearance.applyTheme(to: panel) }
        }
        panel.center()
        return panel
    }

    static func prepareThemeForTesting() {
        if shared.panel == nil { shared.panel = shared.makePanel() }
    }
    static var configuredAppearanceForTesting: NSAppearance.Name? { shared.panel?.appearance?.name }
}

/// 版本信息（诊断 / 许可；反馈与安全渠道为窗口按钮，ADR-079/080）。
enum AboutUI {
    /// 版本信息正文：诊断 + 许可（可整段复制到反馈里）。
    static func text() -> String {
        """
        \(FeedbackUI.diagnostics())
        许可证：GPL-3.0-or-later
        默认离线 · 零遥测 · 无账号
        """
    }

    static func show() {
        InfoWindow.show(
            title: "版本信息", text: text(), allowsCopy: true,
            links: [
                InfoLink(title: "反馈问题", url: FeedbackUI.issuesURL),
                InfoLink(title: "反馈漏洞", url: FeedbackUI.securityURL),
            ])
    }
}
