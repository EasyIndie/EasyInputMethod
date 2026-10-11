// 候选窗：纯代码绘制的无边框 NSPanel（不使用 Interface Builder）。
//
// 当前页候选共享渲染，超过屏幕宽度时自动竖排。
// 候选支持鼠标点选；可显示一个紧凑状态徽标（模式/中英/全角，T-MVP-06）。

import Cocoa

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
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
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

        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 6
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.borderWidth = 1
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(
                equalTo: container.topAnchor, constant: 5 + Self.verticalNudge),
            stack.bottomAnchor.constraint(
                equalTo: container.bottomAnchor, constant: -(5 - Self.verticalNudge)),
        ])
        panel.contentView = container
        // 空闲不轮询：主题计时器只在候选窗可见时运行（MVP-13）。
        for label in [pageLabel, statusLabel, separatorLabel] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
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
        switch ImeConfig.string("appearance.theme") {
        case "light": panel.appearance = NSAppearance(named: .aqua)
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        default: panel.appearance = nil
        }
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
            string: "\(index + 1).\(candidate.text)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.labelColor,
            ])
        if showSource {
            text.append(
                NSAttributedString(
                    string: " " + candidate.source.label,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: 11),
                        .foregroundColor: NSColor.secondaryLabelColor,
                    ]))
        }
        return text
    }

    /// Refresh visible candidates using the current appearance.
    ///
    /// `status`（可选）为紧凑状态徽标（模式/中英/全角），仅在非空时显示。
    func update(
        candidates: [ImeCandidate], pageIndex: Int = 0, pageCount: Int = 1, status: String? = nil
    ) {
        refreshAppearance()

        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
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
            label.onClick = { [weak self] in self?.onSelect?(i) }
            // 内容变化后复位悬停，避免旧高亮残留（标签会被复用）。
            label.setHovered(false)
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        }
        renderedCount = candidates.count
        if !candidates.isEmpty, pageCount > 1 {
            pageLabel.stringValue = "\(pageIndex + 1)/\(pageCount)  −/= 翻页"
            stack.addArrangedSubview(pageLabel)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        panel.setContentSize(
            NSSize(width: max(fitting.width + 20, 44), height: max(fitting.height + 10, 28)))
    }

    /// 供自测：模拟点击第 `index` 个候选（不经过真实鼠标事件）。
    func simulateClick(at index: Int) {
        onSelect?(index)
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
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        if stack.fittingSize.width + 20 > area.width {
            stack.orientation = .vertical
            stack.alignment = .leading
            widthConstraints = stack.arrangedSubviews.map {
                $0.widthAnchor.constraint(lessThanOrEqualToConstant: max(1, area.width - 20))
            }
            NSLayoutConstraint.activate(widthConstraints)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
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
