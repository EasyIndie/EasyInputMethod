// 统一状态反馈：菜单命令与快捷键改变状态后，在光标附近短暂显示新状态。
//
// ADR-211：只做「确认」，不承载操作；不抢焦点、不接收鼠标、不写入配置。
// 关闭动画遵循系统「减弱动态效果」；VoiceOver 通过 announcement 播报。

import AppKit

/// 状态到提示文案的唯一映射；菜单标题与 HUD 共用同一份语义。
enum StateFeedback {
    static func mode(_ mode: String) -> String {
        switch mode {
        case "wubi": return "五笔模式"
        case "pinyin": return "拼音模式"
        default: return "混输模式"
        }
    }

    static func language(_ english: Bool) -> String { english ? "英文" : "中文" }
    static func width(_ fullWidth: Bool) -> String { fullWidth ? "全角" : "半角" }
    static func punctuation(_ chinese: Bool) -> String { chinese ? "中文标点" : "英文标点" }
    static func variant(_ traditional: Bool) -> String { traditional ? "繁体" : "简体" }
    static func learning(_ shown: Bool) -> String { shown ? "学习区：开" : "学习区：关" }
}

/// 供离屏快照与正式浮层共用的胶囊视图。
final class StateHUDView: NSView {
    static let height: CGFloat = 36
    static let horizontalPadding: CGFloat = 16
    static let minimumWidth: CGFloat = 72

    private let label = NSTextField(labelWithString: "")
    let message: String

    init(message: String) {
        self.message = message
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.actions = ["backgroundColor": NSNull(), "borderColor": NSNull()]
        label.stringValue = message
        label.font = .systemFont(ofSize: 15.5, weight: .medium)
        label.alignment = .center
        label.usesSingleLineMode = true
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(message)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var preferredSize: NSSize {
        let width = (message as NSString).size(withAttributes: [.font: label.font as Any]).width
        return NSSize(width: max(Self.minimumWidth, ceil(width) + Self.horizontalPadding * 2),
            height: Self.height)
    }

    func updateColors(for appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.96).cgColor
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.7).cgColor
            label.textColor = .labelColor
        }
    }

    override func layout() {
        super.layout()
        label.sizeToFit()
        label.frame = NSRect(x: 0, y: (bounds.height - label.frame.height) / 2,
            width: bounds.width, height: label.frame.height)
    }

    /// 离屏渲染，供 `make macos-ui-snapshots` 与回归比较。
    static func renderForTesting(message: String, appearance: NSAppearance) -> NSBitmapImageRep? {
        var image: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            let view = StateHUDView(message: message)
            view.appearance = appearance
            view.frame = NSRect(origin: .zero, size: view.preferredSize)
            view.updateColors(for: appearance)
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            image = ImeAppearance.opaqueSnapshot(bitmap, background: .windowBackgroundColor)
        }
        return image
    }
}

/// 光标跟随：插入点上方 8pt，水平居中并夹在屏幕可见区内。
enum StateHUDLayout {
    static let gap: CGFloat = 8

    static func isValid(caret: NSRect?) -> Bool {
        guard let caret else { return false }
        // 插入点矩形经常宽度为 0（只有行高），宽度不参与有效性判断。
        return caret.width >= 0 && caret.height > 0
            && caret.origin.x.isFinite && caret.origin.y.isFinite
    }

    static func frame(size: NSSize, caret: NSRect, visibleFrame: NSRect) -> NSRect {
        var origin = NSPoint(x: caret.midX - size.width / 2, y: caret.maxY + gap)
        origin.x = min(max(origin.x, visibleFrame.minX + gap), visibleFrame.maxX - size.width - gap)
        origin.y = min(max(origin.y, visibleFrame.minY + gap), visibleFrame.maxY - size.height - gap)
        return NSRect(origin: origin, size: size)
    }
}

/// 生命周期；同一时刻只有一个浮层复用。
final class StateHUDController {
    static let shared = StateHUDController()

    /// 正式宿主用 1.15s；测试可调小。
    var holdSeconds: TimeInterval = 1.15
    private var panel: NSPanel?
    private var view: StateHUDView?
    private var hideWorkItem: DispatchWorkItem?

    /// 离屏/无窗口测试（`.prohibited`）不创建浮层，避免污染无头回归。
    private var disabled: Bool {
        ProcessInfo.processInfo.environment["LAMPYRIS_ACCEPTANCE_OUTPUT"] != nil
            || NSApp.activationPolicy() == .prohibited
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 96, height: StateHUDView.height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        return panel
    }

    /// 仅在有聚焦输入框且取到有效光标矩形时显示；取不到就不显示（对齐系统输入源提示）。
    func show(_ message: String, caret: NSRect?) {
        guard !disabled, !message.isEmpty, StateHUDLayout.isValid(caret: caret) else { return }
        guard let caret else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        ImeAppearance.applyTheme(to: panel)

        let view: StateHUDView
        if let existing = self.view, existing.message == message {
            view = existing
        } else {
            view = StateHUDView(message: message)
            self.view = view
            panel.contentView = view
        }
        let size = view.preferredSize
        view.frame = NSRect(origin: .zero, size: size)
        view.updateColors(for: panel.effectiveAppearance)

        let screens = NSScreen.screens
        let center = NSPoint(x: caret.midX, y: caret.midY)
        let screen = screens.first { $0.frame.contains(center) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        panel.setFrame(StateHUDLayout.frame(size: size, caret: caret, visibleFrame: visible),
            display: false)
        panel.invalidateShadow()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.hide() }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds, execute: item)

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if panel.isVisible {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        } else {
            panel.alphaValue = reduceMotion ? 1 : 0
            panel.orderFrontRegardless()
            if !reduceMotion {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.08
                    panel.animator().alphaValue = 1
                }
            }
        }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
            userInfo: [.announcement: message,
                       .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard let panel, panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                panel.orderOut(nil)
            }
        }
    }

    /// 供测试断言当前文案。
    var currentMessage: String? { view?.message }
}
