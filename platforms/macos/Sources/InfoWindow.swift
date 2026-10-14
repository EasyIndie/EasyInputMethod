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
    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

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
        announceStatus()
    }

    @objc private func copyAddress() { reportCopy(Self.copy(fallbackAddress.stringValue, to: .general)) }

    private func finishOpen(_ url: URL, succeeded: Bool, presentation: UUID) {
        guard presentation == presentationID else { return }
        status.stringValue = succeeded ? "已交给默认浏览器打开。" : "打开失败，请复制地址到浏览器。"
        status.textColor = succeeded ? ImeAppearance.secondaryText : ImeAppearance.errorText
        fallbackAddress.stringValue = succeeded ? "" : url.absoluteString
        fallbackAddress.isHidden = succeeded
        copyAddressButton.isHidden = succeeded
        announceStatus()
    }
    private func announceStatus() {
        if panel?.isVisible == true { NSAccessibility.post(element: status, notification: .valueChanged) }
    }
    @objc private func displayOptionsChanged() {
        if let panel { ImeAppearance.applyTheme(to: panel) }
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
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

/// Product identity is separate from the diagnostic text that people explicitly copy.
final class AboutPanel: NSObject, NSWindowDelegate {
    static let shared = AboutPanel()
    private var panel: NSPanel?
    private let status = NSTextField(labelWithString: "")

    func prepare(icon: NSImage? = nil) {
        guard panel == nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 450, height: 324),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "关于萤火虫"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let content = AboutContentView(frame: NSRect(x: 0, y: 0, width: 450, height: 324))
        panel.contentView = content
        self.panel = panel
        let image = NSImageView(frame: NSRect(x: 188, y: 18, width: 74, height: 74))
        image.image = icon ?? Bundle.main.url(forResource: "Lampyris", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) } ?? NSImage(named: NSImage.applicationIconName)
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityLabel("萤火虫应用图标")
        content.addSubview(image)
        func label(_ text: String, y: CGFloat, size: CGFloat, strong: Bool = false) {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: size, weight: strong ? .semibold : .regular)
            label.textColor = strong ? .labelColor : ImeAppearance.secondaryText
            label.alignment = .center
            label.frame = NSRect(x: 16, y: y, width: 418, height: size + 9)
            content.addSubview(label)
        }
        label("萤火虫", y: 107, size: 22, strong: true)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        label("\(version ?? "版本信息不可用") · 开源中文输入法", y: 148, size: 12)
        label("五笔优先，拼音兜底。默认离线。", y: 187, size: 13)
        let copy = NSButton(title: "复制诊断", target: self, action: #selector(copyDiagnostics(_:)))
        copy.bezelStyle = .rounded
        copy.frame = NSRect(x: 99, y: 229, width: 116, height: 30)
        copy.setAccessibilityHelp("仅复制本地版本与环境信息，不发送任何诊断。")
        content.addSubview(copy)
        let feedback = NSPopUpButton(frame: NSRect(x: 231, y: 229, width: 120, height: 30), pullsDown: true)
        feedback.addItems(withTitles: ["反馈问题…", "报告问题…", "报告安全漏洞…"])
        feedback.target = self
        feedback.action = #selector(openFeedback(_:))
        feedback.setAccessibilityLabel("选择问题或安全漏洞反馈渠道")
        content.addSubview(feedback)
        status.frame = NSRect(x: 16, y: 265, width: 418, height: 18)
        status.font = .systemFont(ofSize: 11)
        status.textColor = ImeAppearance.secondaryText
        status.alignment = .center
        status.stringValue = ""
        status.setAccessibilityLabel("操作结果")
        content.addSubview(status)
        label("GPL-3.0-or-later", y: 287, size: 11)
        ImeAppearance.applyTheme(to: panel)
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in
            guard key == "appearance.theme", let panel = self?.panel else { return }
            ImeAppearance.applyTheme(to: panel)
        }
        panel.center()
    }

    func show() {
        prepare()
        NSApp.activate(ignoringOtherApps: true)
        status.stringValue = ""
        panel?.makeKeyAndOrderFront(nil)
    }

    @objc private func copyDiagnostics(_ sender: Any?) {
        _ = copyDiagnostics(to: .general)
    }
    @discardableResult
    func copyDiagnostics(to pasteboard: NSPasteboard) -> Bool {
        let copied = InfoWindow.copy(AboutUI.text(), to: pasteboard)
        status.stringValue = copied ? "已复制诊断；尚未发送。" : "复制失败，请重试。"
        if let panel, panel.isVisible { NSAccessibility.post(element: status, notification: .valueChanged) }
        return copied
    }
    @objc private func openFeedback(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem > 0 else { return }
        let url = sender.indexOfSelectedItem == 2 ? FeedbackUI.securityURL : FeedbackUI.issuesURL
        let opened = NSWorkspace.shared.open(url)
        status.stringValue = opened ? "已交给默认浏览器打开。" : "打开失败，已保留反馈地址。"
        if !opened {
            InfoWindow.show(title: "无法打开反馈", text: "请复制地址后手动打开：\n" + url.absoluteString,
                allowsCopy: true, links: [InfoLink(title: "重新打开…", url: url)])
        }
    }
    func windowWillClose(_ notification: Notification) { panel = nil; status.stringValue = "" }
    var isVisibleForTesting: Bool { panel?.isVisible == true }
    var statusForTesting: String { status.stringValue }
    func renderForTesting(appearance: NSAppearance, icon: NSImage) -> NSBitmapImageRep? {
        prepare(icon: icon)
        guard let panel, let view = panel.contentView else { return nil }
        panel.appearance = appearance
        var image: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            image = ImeAppearance.opaqueSnapshot(bitmap, background: .windowBackgroundColor)
        }
        return image
    }
}
private final class AboutContentView: NSView {
    override var isFlipped: Bool { true }
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

    static func show() { AboutPanel.shared.show() }
}
