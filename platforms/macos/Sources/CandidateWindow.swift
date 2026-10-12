// 候选窗：纯代码绘制的无边框 NSPanel（不使用 Interface Builder）。
//
// 当前页候选共享渲染，超过屏幕宽度时自动竖排。
// 候选支持鼠标点选；可显示一个紧凑状态徽标（模式/中英/全角，T-MVP-06）。

import Cocoa

/// Colors used by custom text; resolve them in the view's actual appearance.
enum ImeAppearance {
    static func applyTheme(to window: NSWindow) {
        switch ImeConfig.string("appearance.theme") {
        case "light": window.appearance = NSAppearance(named: .aqua)
        case "dark": window.appearance = NSAppearance(named: .darkAqua)
        default: window.appearance = nil
        }
    }

    static let secondaryText = NSColor(name: nil) { appearance in
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return resolved.withAlphaComponent(0.78)
    }
    static let errorText = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 1, green: 0.6, blue: 0.6, alpha: 1)
        }
        return NSColor(srgbRed: 0.65, green: 0.1, blue: 0.1, alpha: 1)
    }

    static func contrast(_ foreground: NSColor, over background: NSColor) -> CGFloat {
        guard let fg = foreground.usingColorSpace(.sRGB), let bg = background.usingColorSpace(.sRGB) else { return 0 }
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        func luminance(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGFloat {
            0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let alpha = fg.alphaComponent
        let top = luminance(fg.redComponent * alpha + bg.redComponent * (1 - alpha),
            fg.greenComponent * alpha + bg.greenComponent * (1 - alpha),
            fg.blueComponent * alpha + bg.blueComponent * (1 - alpha))
        let bottom = luminance(bg.redComponent, bg.greenComponent, bg.blueComponent)
        return (max(top, bottom) + 0.05) / (min(top, bottom) + 0.05)
    }

    static func hoverBackground() -> NSColor {
        guard let bg = NSColor.windowBackgroundColor.usingColorSpace(.sRGB),
            let tint = NSColor.selectedContentBackgroundColor.usingColorSpace(.sRGB)
        else { return .windowBackgroundColor }
        return NSColor(srgbRed: bg.redComponent * 0.7 + tint.redComponent * 0.3,
            green: bg.greenComponent * 0.7 + tint.greenComponent * 0.3,
            blue: bg.blueComponent * 0.7 + tint.blueComponent * 0.3, alpha: 1)
    }

    static func opaqueSnapshot(_ image: NSBitmapImageRep, background: NSColor) -> NSBitmapImageRep? {
        guard let output = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: image.pixelsWide, pixelsHigh: image.pixelsHigh, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: output)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh)
        background.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
        return output
    }
}

/// 可点击的候选标签：单击即选中该候选；鼠标悬停时高亮（体验打磨）。
final class CandidateLabel: NSTextField {
    var onClick: (() -> Void)?
    private(set) var isHovered = false
    private var hoverTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUpLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUpLayer()
    }

    private func setUpLayer() {
        wantsLayer = true
        layer?.cornerRadius = 4
        setAccessibilityRole(.button)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick, !isHidden else { return false }
        onClick()
        return true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    /// 悬停跟踪：`.inVisibleRect` 让系统在标签被复用/移动后自动更新区域。
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea { removeTrackingArea(hoverTrackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// 切换悬停高亮；重复设置同一状态不触发重绘。
    func setHovered(_ hovered: Bool) {
        guard isHovered != hovered else { return }
        isHovered = hovered
        guard wantsLayer else { return }
        layer?.backgroundColor =
            hovered
            ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor
            : nil
    }
}

final class CandidateWindow {
    private let panel: NSPanel
    private let stack: NSStackView
    private let rows: NSStackView
    private let hintLabel = NSTextField(labelWithString: "")
    private var themeTimer: Timer?
    private let pageLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let separatorLabel = NSTextField(labelWithString: "│")
    private var labels: [CandidateLabel] = []
    private var renderedCount = 0
    private var widthConstraints: [NSLayoutConstraint] = []

    /// 光学垂直微调：无边框标签的文本贴在行盒顶部，CJK 字形重心偏上；
    /// 下移让字形视觉居中（离屏像素实测，见预览冒烟 `DEBUG3`）。
    private static let verticalNudge = -NSFont.systemFont(ofSize: 16).descender * 0.75

    /// 点击第 `index` 个候选时回调（由宿主执行选字/上屏）。
    var onSelect: ((Int) -> Void)?

    var frame: NSRect { panel.frame }

    /// 当前显示的状态徽标（无则为 nil），供自测断言。
    var displayedStatus: String? {
        stack.arrangedSubviews.contains(statusLabel) ? statusLabel.stringValue : nil
    }
    var configuredAppearanceForTesting: NSAppearance.Name? { panel.appearance?.name }

    /// 当前已渲染的候选文本（含来源标签），供自测断言。
    var displayedCandidateTexts: [String] { labels.prefix(renderedCount).map(\.stringValue) }

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 30),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 14
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        rows = NSStackView(views: [stack])
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 4
        rows.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            rows.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            rows.topAnchor.constraint(
                equalTo: container.topAnchor, constant: 5 + Self.verticalNudge),
            rows.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -(5 - Self.verticalNudge)),
        ])
        panel.contentView = container
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = ImeAppearance.secondaryText
        hintLabel.lineBreakMode = .byTruncatingTail
        // 空闲不轮询：主题计时器只在候选窗可见时运行（MVP-13）。
        for label in [pageLabel, statusLabel, separatorLabel] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = ImeAppearance.secondaryText
        }
        // Warm Chinese font/layout while hidden, before the first input event.
        update(candidates: [ImeCandidate(text: "萤火虫", code: "", source: .codeTable, isPrefix: false)])
        update(candidates: [])
    }

    deinit { themeTimer?.invalidate() }

    /// 可见期间刷新主题；隐藏时停表，避免空闲唤醒（MVP-13）。
    private func startThemeTimer() {
        guard themeTimer == nil else { return }
        themeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshAppearance()
        }
    }

    private func stopThemeTimer() {
        themeTimer?.invalidate()
        themeTimer = nil
    }

    func refreshAppearance() {
        ImeAppearance.applyTheme(to: panel)
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            panel.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            panel.contentView?.layer?.borderColor = NSColor.separatorColor.cgColor
        }
    }

    /// 候选文本 +（可选）来源标签的富文本。
    private static func render(index: Int, _ candidate: ImeCandidate, showSource: Bool)
        -> NSAttributedString
    {
        let text = NSMutableAttributedString(
            string: "\(index + 1). ",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: ImeAppearance.secondaryText,
            ])
        text.append(NSAttributedString(string: candidate.text, attributes: [
            .font: NSFont.systemFont(ofSize: 16, weight: index == 0 ? .semibold : .regular),
            .foregroundColor: NSColor.labelColor,
        ]))
        if showSource {
            text.append(
                NSAttributedString(
                    string: " " + candidate.source.label,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: ImeAppearance.secondaryText,
                    ]))
        }
        return text
    }

    /// Refresh visible candidates using the current appearance.
    ///
    /// `status`（可选）为紧凑状态徽标（模式/中英/全角），仅在非空时显示。
    func update(
        candidates: [ImeCandidate], pageIndex: Int = 0, pageCount: Int = 1, status: String? = nil,
        hint: String? = nil
    ) {
        refreshAppearance()

        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        hintLabel.removeFromSuperview()
        if let hint, !hint.isEmpty, !candidates.isEmpty {
            hintLabel.stringValue = hint
            hintLabel.toolTip = hint
            hintLabel.setAccessibilityLabel(hint)
            rows.addArrangedSubview(hintLabel)
        }
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
        }
        for label in labels {
            label.onClick = nil
            label.setAccessibilityElement(false)
        }
        // 状态徽标：模式/中英/全角（T-MVP-06）。
        if let status, !status.isEmpty {
            statusLabel.stringValue = status
            statusLabel.toolTip = status
            stack.addArrangedSubview(statusLabel)
            stack.addArrangedSubview(separatorLabel)
        }
        // 仅在当前页出现多种来源时标注，避免常态噪声（ADR-057）。
        let showSources = Set(candidates.map(\.source)).count > 1
        for (i, candidate) in candidates.enumerated() {
            if i == labels.count { labels.append(CandidateLabel(labelWithString: "")) }
            let label = labels[i]
            label.attributedStringValue = Self.render(index: i, candidate, showSource: showSources)
            label.lineBreakMode = .byTruncatingTail
            label.usesSingleLineMode = true
            label.toolTip = candidate.text
            label.setAccessibilityElement(true)
            label.setAccessibilityLabel("第\(i + 1)项，\(candidate.text)，\(candidate.source.label)")
            label.onClick = { [weak self] in self?.onSelect?(i) }
            // 内容变化后复位悬停，避免旧高亮残留（标签会被复用）。
            label.setHovered(false)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        }
        renderedCount = candidates.count
        if !candidates.isEmpty, pageCount > 1 {
            let commaKeys = ImeConfig.bool("candidate.page_with_comma") ? " · ,/." : ""
            pageLabel.stringValue = "\(pageIndex + 1)/\(pageCount)  −/= · PgUp/PgDn\(commaKeys)"
            stack.addArrangedSubview(pageLabel)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = rows.fittingSize
        panel.setContentSize(
            NSSize(width: max(fitting.width + 20, 44), height: max(fitting.height + 10, 28)))
    }

    /// 供自测：模拟点击第 `index` 个候选（不经过真实鼠标事件）。
    func simulateClick(at index: Int) {
        onSelect?(index)
    }

    func accessiblePressForTesting(at index: Int) -> Bool {
        guard index >= 0, index < labels.count else { return false }
        return labels[index].accessibilityPerformPress()
    }

    /// 供自测：模拟鼠标悬停第 `index` 个候选（不经过真实鼠标事件）。
    func simulateHover(at index: Int, _ hovered: Bool) {
        guard index >= 0, index < renderedCount else { return }
        labels[index].setHovered(hovered)
    }

    /// 供自测：第 `index` 个候选当前是否处于悬停高亮。
    func isHovered(at index: Int) -> Bool {
        guard index >= 0, index < renderedCount else { return false }
        return labels[index].isHovered
    }

    /// 供自测：第 `index` 个候选是否具备可渲染高亮的图层（防止高亮静默失效）。
    func isHoverRenderable(at index: Int) -> Bool {
        guard index >= 0, index < renderedCount else { return false }
        return labels[index].wantsLayer
    }

    /// 供自测：容器 bounds 与已渲染候选标签的 frame（容器坐标系），用于垂直居中回归。
    func layoutForTesting() -> (container: NSRect, labels: [NSRect])? {
        guard let container = panel.contentView else { return nil }
        return (
            container.bounds,
            labels.prefix(renderedCount).map { $0.convert($0.bounds, to: container) }
        )
    }

    /// 供自测：把候选窗当前内容渲染为位图（按当前外观），用于浅/暗主题可读性（对比度）断言。
    func renderSnapshotForTesting() -> NSBitmapImageRep? {
        guard let view = panel.contentView, view.bounds.width > 1, view.bounds.height > 1,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 从多个屏幕 frame 中选出与光标最相关的一个：
    /// 优先相交面积最大者（副屏可为负坐标）；退而取包含光标中心的屏幕；再退回第一个。
    /// 独立于 `NSScreen` 实例，便于隔离几何测试（多屏 / 负坐标 / 高分屏）。
    static func bestScreenIndex(for caret: NSRect, among frames: [NSRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        var bestIndex: Int?
        var bestOverlap: CGFloat = 0
        for (index, frame) in frames.enumerated() where frame.intersects(caret) {
            let overlap = frame.intersection(caret)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if bestIndex == nil || area > bestOverlap {
                bestIndex = index
                bestOverlap = area
            }
        }
        if let bestIndex { return bestIndex }
        let center = NSPoint(x: caret.midX, y: caret.midY)
        return frames.firstIndex { $0.contains(center) } ?? 0
    }

    /// 在光标矩形上方显示。
    func show(at caret: NSRect) {
        refreshAppearance()
        startThemeTimer()
        // 用 frame 选屏、visibleFrame 钳制，避免跨屏/菜单栏区域错位（体验打磨）。
        let screens = NSScreen.screens
        let index = Self.bestScreenIndex(for: caret, among: screens.map(\.frame))
        let screen = index.flatMap { $0 < screens.count ? screens[$0] : nil } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        layout(at: caret, within: area)
        panel.orderFront(nil)
    }

    /// Bound geometry independently of the display server for deterministic checks.
    func layout(at caret: NSRect, within area: NSRect) {
        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        widthConstraints.append(hintLabel.widthAnchor.constraint(lessThanOrEqualToConstant: max(1, area.width - 20)))
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        if stack.fittingSize.width + 20 > area.width {
            stack.orientation = .vertical
            stack.alignment = .leading
            widthConstraints += stack.arrangedSubviews.map {
                $0.widthAnchor.constraint(lessThanOrEqualToConstant: max(1, area.width - 20))
            }
        }
        NSLayoutConstraint.activate(widthConstraints)
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = rows.fittingSize
        panel.setContentSize(NSSize(width: min(area.width, max(fitting.width + 20, 44)),
            height: min(area.height, max(fitting.height + 10, 28))))
        let size = panel.frame.size
        let x = max(area.minX, min(caret.minX, area.maxX - size.width))
        let preferredY = caret.maxY + 4
        let y = preferredY + size.height <= area.maxY ? preferredY : caret.minY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: max(area.minY, min(y, area.maxY - size.height))))
    }

    func hide() {
        stopThemeTimer()
        panel.orderOut(nil)
    }
}
