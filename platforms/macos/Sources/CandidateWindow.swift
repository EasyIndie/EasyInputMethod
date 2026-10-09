// 候选窗：纯代码绘制的无边框 NSPanel（不使用 Interface Builder）。
//
// 当前页候选共享渲染，超过屏幕宽度时自动竖排。

import Cocoa

final class CandidateWindow {
    private let panel: NSPanel
    private let stack: NSStackView
    private var themeTimer: Timer?
    private let pageLabel = NSTextField(labelWithString: "")
    private var labels: [NSTextField] = []
    private var renderedCount = 0
    private var widthConstraints: [NSLayoutConstraint] = []

    var frame: NSRect { panel.frame }

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
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -5),
        ])
        panel.contentView = container
        themeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshAppearance()
        }
        // Warm Chinese font/layout while hidden, before the first input event.
        update(candidates: [ImeCandidate(text: "萤火虫", code: "", source: .codeTable, isPrefix: false)])
        update(candidates: [])
    }

    deinit { themeTimer?.invalidate() }

    private func refreshAppearance() {
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
    func update(candidates: [ImeCandidate], pageIndex: Int = 0, pageCount: Int = 1) {
        refreshAppearance()

        NSLayoutConstraint.deactivate(widthConstraints)
        widthConstraints = []
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 14
        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
        }
        // 仅在当前页出现多种来源时标注，避免常态噪声（ADR-057）。
        let showSources = Set(candidates.map(\.source)).count > 1
        for (i, candidate) in candidates.enumerated() {
            if i == labels.count { labels.append(NSTextField(labelWithString: "")) }
            let label = labels[i]
            label.attributedStringValue = Self.render(index: i, candidate, showSource: showSources)
            label.lineBreakMode = .byTruncatingTail
            label.usesSingleLineMode = true
            label.toolTip = candidate.text
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(label)
        }
        renderedCount = candidates.count
        if !candidates.isEmpty, pageCount > 1 {
            pageLabel.stringValue = "\(pageIndex + 1)/\(pageCount)  −/= 翻页"
            pageLabel.font = NSFont.systemFont(ofSize: 11)
            pageLabel.textColor = .secondaryLabelColor
            stack.addArrangedSubview(pageLabel)
        }
        panel.contentView?.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize
        panel.setContentSize(
            NSSize(width: max(fitting.width + 20, 44), height: max(fitting.height + 10, 28)))
    }

    /// 在光标矩形上方显示。
    func show(at caret: NSRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
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
        panel.orderOut(nil)
    }
}
