import Cocoa

/// 宿主内完整使用指南（ADR-351，取代 ADR-343 的一页提示）。
///
/// 首次启用自动打开一次（标记仍为 `onboarding-done`）；之后可从输入法菜单「使用指南…」随时重看。
/// 纯本地、无网络；快捷键文案从当前配置读取，用户改过也能显示正确。
/// 一条说明：前置键帽（可为空）+ 一句短文案。
struct OnboardingBullet {
    let keys: [String]
    let text: String

    var spokenText: String {
        (keys + [text]).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct OnboardingStep {
    let symbol: String
    let title: String
    /// 一句话说清这一步解决什么问题。
    let summary: String
    let bullets: [OnboardingBullet]

    /// 无障碍与测试用的纯文本：摘要 + 逐条说明。
    var body: String { ([summary] + bullets.map(\.spokenText)).joined(separator: "\n") }
}

enum OnboardingGuide {
    static func steps() -> [OnboardingStep] {
        [
            OnboardingStep(
                symbol: "sparkles",
                title: "欢迎使用萤火虫",
                summary: "五笔优先，想不起编码时用拼音兜底。",
                bullets: [
                    OnboardingBullet(keys: [], text: "全部在本机完成：离线、无账号、不上传"),
                    OnboardingBullet(keys: [], text: "候选、学习区、练习共用同一份本地数据"),
                ]),
            OnboardingStep(
                symbol: "keyboard",
                title: "切换输入状态",
                summary: "状态键都是单个 ⌥，随时可在设置里改。",
                bullets: [
                    OnboardingBullet(keys: [hotkey("hotkey.toggle_mode")], text: "混合 / 五笔 / 拼音 循环"),
                    OnboardingBullet(keys: [hotkey("hotkey.toggle_english")], text: "中英切换"),
                    OnboardingBullet(keys: [hotkey("hotkey.toggle_punctuation"),
                                            hotkey("hotkey.toggle_width"),
                                            hotkey("hotkey.toggle_variant")],
                                     text: "标点 · 全半角 · 简繁"),
                ]),
            OnboardingStep(
                symbol: "character.book.closed",
                title: "学习区",
                summary: "边打边看拆解，不打乱候选顺序。",
                bullets: [
                    OnboardingBullet(keys: [hotkey("hotkey.toggle_wubi_learning")], text: "显示或隐藏学习区"),
                    OnboardingBullet(keys: [], text: "显示完整码、字根、识别码与简码"),
                    OnboardingBullet(keys: [], text: "只做提示：不参与排序，不带练习成绩"),
                ]),
            OnboardingStep(
                symbol: "graduationcap",
                title: "练习与跟打",
                summary: "按掌握度逐级解锁，进度只存本机。",
                bullets: [
                    OnboardingBullet(keys: [hotkey("hotkey.open_practice")], text: "打开练习"),
                    OnboardingBullet(keys: [], text: "字根 → 一级 → 二级 → 三级 → 完整码 → 词组 → 识别码（三级简码只对官方简码表内的字成立）"),
                    OnboardingBullet(keys: [], text: "练习窗口里可进入「文章跟打」；进度可一键重置"),
                ]),
            OnboardingStep(
                symbol: "textformat.abc",
                title: "符号与设置",
                summary: "一个快捷键找符号，一个入口改偏好。",
                bullets: [
                    OnboardingBullet(keys: [hotkey("hotkey.open_symbols")], text: "符号与 emoji 面板（拼音 / 英文搜索）"),
                    OnboardingBullet(keys: [hotkey("hotkey.open_settings")], text: "设置：词库、快捷键、学习选项"),
                    OnboardingBullet(keys: [], text: "配置只有一个来源，改完即时生效"),
                ]),
            OnboardingStep(
                symbol: "lock.shield",
                title: "隐私与更新",
                summary: "输入引擎默认离线，这是可验证的承诺。",
                bullets: [
                    OnboardingBullet(keys: [], text: "零网络、零遥测，不记录输入内容"),
                    OnboardingBullet(keys: [], text: "更新检查只在你点菜单项时运行"),
                    OnboardingBullet(keys: [], text: "更新程序与输入法分离，可单独审计"),
                ]),
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
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let bulletsStack = NSStackView()
    private let stepLabel = NSTextField(labelWithString: "")
    private let stepDots = NSStackView()
    private var contentStack: NSStackView?
    private let backButton = NSButton(title: "上一步", target: nil, action: nil)
    private let nextButton = NSButton(title: "下一步", target: nil, action: nil)

    var isVisible: Bool { window?.isVisible == true }
    var stepCountForTesting: Int { steps.count }
    var currentTitleForTesting: String { titleLabel.stringValue }
    /// 测试用：当前步骤的结构化纯文本（摘要 + 逐条）。
    var currentBodyForTesting: String {
        steps.indices.contains(index) ? steps[index].body : ""
    }

    /// 显示指南；`firstRun` 只用于文案/日志，不改变页面内容。
    func show(firstRun: Bool = false) {
        prepare()
        steps = OnboardingGuide.steps()
        guard !steps.isEmpty else { return }
        index = 0
        update()
        if NSApp.activationPolicy() == .prohibited { NSApp.setActivationPolicy(.accessory) }
        NSApp.activate(ignoringOtherApps: true)
        if let window { WindowPlacement.place(window) }
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
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 336),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "萤火虫使用指南"
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.onKey = { [weak self] key in self?.handleKey(key) ?? false }
        ImeAppearance.applyTheme(to: panel)

        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 30).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 30).isActive = true
        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        summaryLabel.font = .systemFont(ofSize: 13.5)
        summaryLabel.textColor = .labelColor
        summaryLabel.preferredMaxLayoutWidth = 440
        summaryLabel.lineBreakMode = .byWordWrapping
        stepLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        stepLabel.textColor = ImeAppearance.secondaryText

        bulletsStack.orientation = .vertical
        bulletsStack.alignment = .leading
        bulletsStack.spacing = 10
        bulletsStack.translatesAutoresizingMaskIntoConstraints = false

        stepDots.orientation = .horizontal
        stepDots.alignment = .centerY
        stepDots.spacing = 5

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .rounded
        backButton.setAccessibilityLabel("上一步")
        nextButton.target = self
        nextButton.action = #selector(goNext)
        nextButton.bezelStyle = .rounded
        nextButton.keyEquivalent = "\r"
        nextButton.setAccessibilityLabel("下一步")

        let titleRow = NSStackView(views: [icon, titleLabel])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 10

        // 左侧结构化文字（目标 + 键帽条目），右侧小尺寸图示，避免正文挤在一起。
        let header = NSStackView(views: [titleRow, summaryLabel, bulletsStack])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 12
        header.translatesAutoresizingMaskIntoConstraints = false

        illustrationBox.wantsLayer = true
        illustrationBox.layer?.cornerRadius = 16
        illustrationBox.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.10).cgColor
        illustrationBox.translatesAutoresizingMaskIntoConstraints = false
        illustration.imageScaling = .scaleProportionallyUpOrDown
        illustration.contentTintColor = .controlAccentColor
        illustration.translatesAutoresizingMaskIntoConstraints = false
        illustrationBox.addSubview(illustration)

        let top = NSStackView(views: [header, illustrationBox])
        top.orientation = .horizontal
        top.alignment = .top
        top.spacing = 20
        top.translatesAutoresizingMaskIntoConstraints = false

        let bottom = NSStackView(views: [stepLabel, stepDots, NSView(), backButton, nextButton])
        bottom.orientation = .horizontal
        bottom.alignment = .centerY
        bottom.spacing = 10

        let content = NSStackView(views: [top, bottom])
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
            header.widthAnchor.constraint(equalTo: top.widthAnchor, constant: -116),
            summaryLabel.widthAnchor.constraint(equalTo: header.widthAnchor),
            bulletsStack.widthAnchor.constraint(equalTo: header.widthAnchor),
            bottom.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -48),
            illustrationBox.widthAnchor.constraint(equalToConstant: 96),
            illustrationBox.heightAnchor.constraint(equalToConstant: 96),
            illustration.centerXAnchor.constraint(equalTo: illustrationBox.centerXAnchor),
            illustration.centerYAnchor.constraint(equalTo: illustrationBox.centerYAnchor),
            illustration.widthAnchor.constraint(equalToConstant: 48),
            illustration.heightAnchor.constraint(equalToConstant: 48),
        ])
        contentStack = content
        window = panel
    }

    private func update() {
        guard steps.indices.contains(index) else { return }
        let step = steps[index]
        icon.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: step.title)
        illustration.image = NSImage(systemSymbolName: step.symbol, accessibilityDescription: step.title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 40, weight: .regular))
        illustrationBox.setAccessibilityLabel("步骤图示：\(step.title)")
        titleLabel.stringValue = step.title
        summaryLabel.stringValue = step.summary
        rebuildBullets(step.bullets)
        stepLabel.stringValue = "\(index + 1) / \(steps.count)"
        rebuildDots()
        backButton.isEnabled = index > 0
        nextButton.title = index == steps.count - 1 ? "完成" : "下一步"
        nextButton.setAccessibilityLabel(nextButton.title)
        resizeToFitContent()
        window?.title = "萤火虫使用指南 — \(step.title)"
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "第 \(index + 1) 步，共 \(steps.count) 步：\(step.title)。\(step.summary)",
                                         .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    /// 内容多高窗口就多高（步骤内容长度不同），避免固定高度留下大片空白。
    private func resizeToFitContent() {
        guard let window, let content = contentStack else { return }
        content.layoutSubtreeIfNeeded()
        let height = max(220, ceil(content.fittingSize.height))
        let width = window.contentLayoutRect.width
        guard abs(window.contentLayoutRect.height - height) > 0.5 else { return }
        // 保持顶边不动：翻页时窗口向上/向下长，不让整窗跳动。
        let top = window.frame.maxY
        window.setContentSize(NSSize(width: width, height: height))
        var frame = window.frame
        frame.origin.y = top - frame.height
        window.setFrame(frame, display: false)
    }

    /// 逐条重建（步骤切换时条目数不同，直接换掉 arranged subviews）。
    private func rebuildBullets(_ bullets: [OnboardingBullet]) {
        for view in bulletsStack.arrangedSubviews {
            bulletsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for bullet in bullets {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8
            if bullet.keys.isEmpty {
                row.addArrangedSubview(BulletDotView())
            } else {
                for key in bullet.keys where !key.isEmpty {
                    row.addArrangedSubview(KeycapView(text: key))
                }
            }
            let text = NSTextField(wrappingLabelWithString: bullet.text)
            text.font = .systemFont(ofSize: 13)
            text.lineBreakMode = .byWordWrapping
            row.addArrangedSubview(text)
            row.setAccessibilityElement(true)
            row.setAccessibilityRole(.staticText)
            row.setAccessibilityLabel(bullet.spokenText)
            bulletsStack.addArrangedSubview(row)
        }
    }

    /// 步骤点：当前位置实心，其余淡色；纯视觉，步骤文字已给出序号。
    private func rebuildDots() {
        for view in stepDots.arrangedSubviews {
            stepDots.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for position in steps.indices {
            let dot = StepDotView(current: position == index)
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 7).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 7).isActive = true
            stepDots.addArrangedSubview(dot)
        }
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

/// 按键徽章：等宽小字 + 圆角浅底，替代把快捷键串在句子里。
///
/// 用 `draw(_:)` 而不是 layer 背景：离屏快照（`cacheDisplay`）只走绘制路径，
/// layer 背景在快照里会丢，导致指南截图看不到键帽。
private final class KeycapView: NSView {
    private let text: String
    private static let font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .medium)

    init(text: String) {
        self.text = text
        super.init(frame: .zero)
        let width = ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 12
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        NSColor.labelColor.withAlphaComponent(0.07).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
        let attributes: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                                            y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }
}

/// 条目前的项目符号：与键帽同一行高，保证有键帽/无键帽两种行对齐。
private final class BulletDotView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 4).isActive = true
        heightAnchor.constraint(equalToConstant: 4).isActive = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}

/// 步骤点：当前位置实心强调色，其余用分割线色。
private final class StepDotView: NSView {
    private let current: Bool

    init(current: Bool) {
        self.current = current
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        (current ? NSColor.controlAccentColor : NSColor.separatorColor).setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
