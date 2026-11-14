import Cocoa

/// 宿主内完整使用指南（ADR-351，取代 ADR-343 的一页提示）。
///
/// 首次启用自动打开一次（标记仍为 `onboarding-done`）；之后可从输入法菜单「使用指南…」随时重看。
/// 纯本地、无网络；快捷键文案从当前配置读取，用户改过也能显示正确。
struct OnboardingStep {
    let symbol: String
    let title: String
    let body: String
}

enum OnboardingGuide {
    static func steps() -> [OnboardingStep] {
        [
            OnboardingStep(
                symbol: "sparkles",
                title: "欢迎使用萤火虫",
                body: "默认混合输入：五笔优先，想不起编码时用拼音兜底。\n"
                    + "所有输入都在本机完成，离线、无账号、不上传。"),
            OnboardingStep(
                symbol: "keyboard",
                title: "切换输入状态",
                body: "\(hotkey("hotkey.toggle_mode")) 切换模式 · \(hotkey("hotkey.toggle_english")) 中英\n"
                    + "\(hotkey("hotkey.toggle_punctuation")) 标点 · \(hotkey("hotkey.toggle_width")) 全/半角"
                    + " · \(hotkey("hotkey.toggle_variant")) 简/繁\n"
                    + "这些快捷键都可以在设置里修改。"),
            OnboardingStep(
                symbol: "character.book.closed",
                title: "学习区",
                body: "\(hotkey("hotkey.toggle_wubi_learning")) 打开学习区：显示完整码、字根、识别码与简码。\n"
                    + "学习区只做提示，不改变候选顺序，也不会把练习成绩带进排序。"),
            OnboardingStep(
                symbol: "graduationcap",
                title: "练习与跟打",
                body: "\(hotkey("hotkey.open_practice")) 打开练习：字根 → 一级简码 → 二级简码 → 三级简码 → 完整码 → 词组 → 识别码，\n"
                    + "按掌握度逐级解锁；练习窗口里也可以进入「文章跟打」。\n"
                    + "进度只写本机，可一键重置。"),
            OnboardingStep(
                symbol: "textformat",
                title: "设置与词库",
                body: "\(hotkey("hotkey.open_settings")) 打开设置；词库分区可以新增、删除、导入和导出本地 TSV。\n"
                    + "配置只有一个来源，修改即时生效。"),
            OnboardingStep(
                symbol: "face.smiling",
                title: "符号与 emoji",
                body: "\(hotkey("hotkey.open_symbols")) 打开符号 / emoji 面板，支持中文、英文和拼音搜索。\n"
                    + "中文状态下按反引号 ` 也能快速打开符号分类。"),
            OnboardingStep(
                symbol: "lock.shield",
                title: "隐私与更新",
                body: "输入引擎零网络、零遥测，不采集输入内容。\n"
                    + "更新检查只在你点击菜单项时运行；更新程序与输入法核心分离。"),
        ]
    }

    /// 按 `config.toml` 的写法显示快捷键，例如 `⌥M`、`⇧`、`未设置`。
    static func hotkey(_ key: String) -> String {
        let binding = ImeConfig.hotkey(key)
        switch binding.kind {
        case 1: return "⇧"
        case 2:
            var text = ""
            if binding.modifiers.contains(.control) { text += "⌃" }
            if binding.modifiers.contains(.option) { text += "⌥" }
            if binding.modifiers.contains(.shift) { text += "⇧" }
            if binding.modifiers.contains(.command) { text += "⌘" }
            return text + binding.equivalent.uppercased()
        default: return "未设置"
        }
    }
}

/// 单例指南窗口：首次启用与菜单入口共用，避免多个窗口堆积。
final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()

    private var window: OnboardingPanel?
    private var steps: [OnboardingStep] = []
    private var index = 0
    private let icon = NSImageView()
    private let illustration = NSImageView()
    private let illustrationBox = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let stepLabel = NSTextField(labelWithString: "")
    private let backButton = NSButton(title: "上一步", target: nil, action: nil)
    private let nextButton = NSButton(title: "下一步", target: nil, action: nil)

    var isVisible: Bool { window?.isVisible == true }
    var stepCountForTesting: Int { steps.count }
    var currentTitleForTesting: String { titleLabel.stringValue }
    var currentBodyForTesting: String { bodyLabel.stringValue }

    /// 显示指南；`firstRun` 只用于文案/日志，不改变页面内容。
    func show(firstRun: Bool = false) {
        prepare()
        steps = OnboardingGuide.steps()
        guard !steps.isEmpty else { return }
        index = 0
        update()
        if NSApp.activationPolicy() == .prohibited { NSApp.setActivationPolicy(.accessory) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        window?.orderOut(nil)
    }

    /// 离屏渲染指南（报告 289）：不显示窗口、不激活 App，供 UI 快照与布局回归使用。
    func renderForTesting(appearance: NSAppearance, step: Int = 0) -> NSBitmapImageRep? {
        prepare()
        steps = OnboardingGuide.steps()
        guard !steps.isEmpty, let panel = window, let view = panel.contentView else { return nil }
        index = min(max(0, step), steps.count - 1)
        update()
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

    private func prepare() {
        guard window == nil else { return }
        let panel = OnboardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "萤火虫使用指南"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onKey = { [weak self] key in self?.handleKey(key) ?? false }
        ImeAppearance.applyTheme(to: panel)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 42).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 42).isActive = true
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .labelColor
        bodyLabel.preferredMaxLayoutWidth = 500
        bodyLabel.lineBreakMode = .byWordWrapping
        stepLabel.font = .systemFont(ofSize: 11)
        stepLabel.textColor = ImeAppearance.secondaryText

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        backButton.setAccessibilityLabel("上一步")
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.setAccessibilityLabel("下一步")

        let bottom = NSStackView(views: [stepLabel, NSView(), backButton, nextButton])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 10

        // 左侧文字 + 右侧大图标：把原来窗口下半部分的空白变成有效信息区（报告 289）。
        let header = NSStackView(views: [icon, titleLabel, bodyLabel])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        illustrationBox.wantsLayer = true
        illustrationBox.layer?.cornerRadius = 18
        illustrationBox.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        illustrationBox.translatesAutoresizingMaskIntoConstraints = false
        illustration.imageScaling = .scaleProportionallyUpOrDown
        illustration.contentTintColor = .controlAccentColor
        illustration.translatesAutoresizingMaskIntoConstraints = false
        illustrationBox.addSubview(illustration)

        let top = NSStackView(views: [header, illustrationBox])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 24
        top.translatesAutoresizingMaskIntoConstraints = false

        let content = NSStackView(views: [top, NSView(), bottom])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 18, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(content)
        guard let host = panel.contentView else { return }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            top.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
            header.widthAnchor.constraint(equalTo: top.widthAnchor, constant: -156),
            bodyLabel.widthAnchor.constraint(equalTo: header.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
            illustrationBox.widthAnchor.constraint(equalToConstant: 132),
            illustrationBox.heightAnchor.constraint(equalToConstant: 132),
            illustration.centerXAnchor.constraint(equalTo: illustrationBox.centerXAnchor),
            illustration.centerYAnchor.constraint(equalTo: illustrationBox.centerYAnchor),
            illustration.widthAnchor.constraint(equalToConstant: 64),
            illustration.heightAnchor.constraint(equalToConstant: 64),
        ])
        panel.center()
        window = panel
    }

    private func update() {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        icon.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: step.title)
        illustration.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: step.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 56, weight: .regular))
        illustrationBox.setAccessibilityLabel("步骤图示：\(step.title)")
        titleLabel.stringValue = step.title
        bodyLabel.stringValue = step.body
        stepLabel.stringValue = "\(index + 1) / \(steps.count)"
        backButton.isEnabled = index > 0
        nextButton.title = index == steps.count - 1 ? "完成" : "下一步"
        nextButton.setAccessibilityLabel(nextButton.title)
        window?.title = "萤火虫使用指南 — \(step.title)"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "第 \(index + 1) 步，共 \(steps.count) 步：\(step.title)",
                                         .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func goNext() {
        guard index + 1 < steps.count else { close(); return }
        index += 1
        update()
    }

    @objc private func goBack() {
        guard index > 0 else { return }
        index -= 1
        update()
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123: goBack(); return true // left
        case 124, 36, 76: goNext(); return true // right/return/enter
        case 53: close(); return true // esc
        default: return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        // 标记在首次弹出前已写入；关闭窗口不重复写。
    }

    // MARK: - 测试

    func prepareForTesting() {
        prepare()
        if steps.isEmpty { steps = OnboardingGuide.steps() }
    }
    func updateForTesting() { update() }
    func nextForTesting() { goNext() }
    func backForTesting() { goBack() }
    var panelForTesting: NSPanel? { window }
}

/// 左右键翻页、Esc 关闭；其余按键交给 AppKit。
private final class OnboardingPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
    override func cancelOperation(_ sender: Any?) {
        orderOut(nil)
    }
}
