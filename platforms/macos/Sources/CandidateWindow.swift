// 候选窗：纯代码绘制的无边框 NSPanel（不使用 Interface Builder）。
//
// P1-M3 只做「能显示 + 数字选择」的最小候选窗；亮/暗主题、翻页、竖排等属 P1-M4。

import Cocoa

final class CandidateWindow {
    private let panel: NSPanel
    private let stack: NSStackView
    private var themeTimer: Timer?

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

    /// Refresh visible candidates using the current appearance.
    func update(candidates: [String]) {
        refreshAppearance()

        for view in stack.arrangedSubviews {
            view.removeFromSuperview()
        }
        for (i, text) in candidates.enumerated() {
            let label = NSTextField(labelWithString: "\(i + 1).\(text)")
            label.font = NSFont.systemFont(ofSize: 16)
            label.textColor = .labelColor
            stack.addArrangedSubview(label)
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
        let size = panel.frame.size
        let x = max(area.minX, min(caret.minX, area.maxX - size.width))
        let preferredY = caret.maxY + 4
        let y = preferredY + size.height <= area.maxY ? preferredY : caret.minY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: max(area.minY, min(y, area.maxY - size.height))))
        panel.orderFront(nil)
    }

    func hide() {
        panel.orderOut(nil)
    }
}
