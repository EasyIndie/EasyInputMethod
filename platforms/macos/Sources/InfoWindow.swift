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
        shared.prepareContent(title: title, text: text, allowsCopy: allowsCopy, links: links)
        NSApp.activate(ignoringOtherApps: true)
        shared.panel?.makeKeyAndOrderFront(nil)
    }

    private func prepareContent(title: String, text: String, allowsCopy: Bool, links: [InfoLink]) {
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
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.setAccessibilityLabel(title + "内容")
        textView.setAccessibilityHelp("只读信息，可选择文本；复制按钮不会发送信息。")
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.autohidesScrollers = true
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

        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.textColor = .labelColor
        status.font = .systemFont(ofSize: 12)
        status.setAccessibilityLabel("操作结果")
        fallbackAddress.font = .systemFont(ofSize: 12)
        fallbackAddress.lineBreakMode = .byCharWrapping
        fallbackAddress.setAccessibilityLabel("打开失败的地址")
        var views: [NSView] = [heading, scroll]
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
        panel.recalculateKeyViewLoop()
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
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.contentMinSize = NSSize(width: 420, height: 300)
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

    static func preparePresentationForTesting(title: String, text: String, allowsCopy: Bool, links: [InfoLink] = []) {
        shared.prepareContent(title: title, text: text, allowsCopy: allowsCopy, links: links)
    }
    static func simulateOpenForTesting(_ url: URL, succeeded: Bool) {
        shared.finishOpen(url, succeeded: succeeded, presentation: shared.presentationID)
    }
    static var isVisibleForTesting: Bool { shared.panel?.isVisible == true }
    static var statusForTesting: String { shared.status.stringValue }
    static func renderSnapshotForTesting(appearance: NSAppearance, minimum: Bool = false) -> NSBitmapImageRep? {
        guard let panel = shared.panel, let view = panel.contentView else { return nil }
        panel.appearance = appearance
        if minimum { panel.setContentSize(panel.contentMinSize) }
        view.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        var output: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            output = ImeAppearance.opaqueSnapshot(rep, background: .windowBackgroundColor)
        }
        return output
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
            title: "关于萤火虫", text: text(), allowsCopy: true,
            links: [
                InfoLink(title: "反馈问题", url: FeedbackUI.issuesURL),
                InfoLink(title: "反馈漏洞", url: FeedbackUI.securityURL),
            ])
    }
}
