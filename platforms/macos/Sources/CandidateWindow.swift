// 候选窗：纯代码绘制的无边框 NSPanel（不使用 Interface Builder）。
//
// 当前页候选共享渲染，超过屏幕宽度时自动竖排。
// ADR-165：输入码、极简候选与非激活分页；来源留在辅助标签，模式留在菜单。

import Cocoa
import CoreText

/// Readable display only; candidate identity and commit text remain in ImeSession.
enum CandidateTextPresentation {
    private static var cache: [String: Bool] = [:]

    static func display(_ text: String, font: NSFont = .systemFont(ofSize: 17)) -> String {
        text.map { character in
            let value = String(character)
            let key = font.fontName + ":" + value
            let supported: Bool
            if let saved = cache[key] { supported = saved }
            else {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [.font: font]))
                let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
                supported = !runs.contains { run in
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard let fallback = attributes[kCTFontAttributeName] else { return false }
                    let name = CTFontCopyPostScriptName(fallback as! CTFont) as String
                    return name.lowercased().contains("lastresort")
                }
                if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
                cache[key] = supported
            }
            return supported ? value : "〔缺字 " + value.unicodeScalars.map { String(format: "U+%X", $0.value) }.joined(separator: "+") + "〕"
        }.joined()
    }
}

/// Colors used by custom text; resolve them in the view's actual appearance.
enum ImeAppearance {
    static func isHighContrast(_ appearance: NSAppearance) -> Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            || appearance.name == .accessibilityHighContrastAqua
            || appearance.name == .accessibilityHighContrastDarkAqua
    }

    static func applyTheme(to window: NSWindow) {
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch ImeConfig.string("appearance.theme") {
        case "light": window.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastAqua : .aqua)
        case "dark": window.appearance = NSAppearance(named: highContrast ? .accessibilityHighContrastDarkAqua : .darkAqua)
        default: window.appearance = nil
        }
    }

    static func secondaryTextColor(for appearance: NSAppearance, highContrast: Bool) -> NSColor {
        var resolved = NSColor.labelColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        return resolved.withAlphaComponent(highContrast ? 1 : 0.78)
    }
    static let secondaryText = NSColor(name: nil) { appearance in
        secondaryTextColor(for: appearance, highContrast: isHighContrast(appearance))
    }
    static func candidateBorderColor(highContrast: Bool) -> NSColor {
        highContrast ? NSColor.labelColor.withAlphaComponent(0.5) : .separatorColor
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

/// 候选文字四周留白：悬停高亮覆盖 label 全框，文字通过 cell 的 drawingRect 内缩。
final class PaddedCandidateCell: NSTextFieldCell {
    static let horizontal: CGFloat = 6
    static let vertical: CGFloat = 2
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        rect.insetBy(dx: Self.horizontal, dy: Self.vertical)
    }
}

/// 可点击的候选标签：单击即选中该候选；鼠标悬停时高亮（体验打磨）。
final class CandidateLabel: NSTextField {
    var onClick: (() -> Void)?
    private(set) var isHovered = false
    private(set) var isKeyboardSelected = false
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
        layer?.actions = ["backgroundColor": NSNull()]
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
        paintSelection()
    }

    func setKeyboardSelected(_ selected: Bool) {
        guard isKeyboardSelected != selected else { return }
        isKeyboardSelected = selected
        paintSelection()
    }

    private func paintSelection() {
        guard wantsLayer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let alpha: CGFloat = isHovered ? 0.30 : isKeyboardSelected ? 0.18 : 0
            layer?.backgroundColor = alpha > 0
                ? NSColor.selectedContentBackgroundColor.withAlphaComponent(alpha).cgColor : nil
        }
    }
    func refreshSelectionAppearance() { paintSelection() }
}

private final class CandidatePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class CandidatePageButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabled, !isHidden else { return false }
        performClick(nil)
        return true
    }
}

private final class CandidateDocument: NSView {
    override var isFlipped: Bool { true }
}

/// Nonactivating teaching extension. It never owns an input session or commits text.
final class WubiLearningView: NSView {
    private var model: WubiLearning?
    private var identity = ""
    private var queryUnavailable = false
    private var expanded = false
    private var expandedCharacters: Set<Int> = []
    private var buttons: [String: NSButton] = [:]
    private var detailScroll: NSScrollView?
    private var detailOrigin = NSPoint.zero
    var onResize: (() -> Void)?
    override var isFlipped: Bool { true }
    var hasContent: Bool { model != nil }
    var expandedForTesting: Bool { expanded }

    func update(_ text: String?) {
        if text != identity {
            clearContent()
            detailOrigin = .zero
            identity = text ?? ""
            if text == nil { expanded = false }
            expandedCharacters.removeAll()
        }
        let result = text.flatMap(WubiLearning.lookup)
        queryUnavailable = text != nil && result == nil
        model = text == nil ? nil : result ?? WubiLearning(code: nil, rule: "学习说明暂缺", characters: [])
        isHidden = model == nil
        if model == nil { clearContent() }
    }

    private func clearContent(dropButtons: Bool = true) {
        func clear(_ view: NSView) {
            if let control = view as? NSControl { control.target = nil; control.action = nil }
            view.subviews.forEach(clear)
        }
        subviews.forEach { clear($0); $0.removeFromSuperview() }
        detailScroll = nil
        if dropButtons { buttons.removeAll() }
    }
    var detailOriginForTesting: NSPoint { detailScroll?.contentView.bounds.origin ?? .zero }
    func scrollDetailsForTesting(_ y: CGFloat) {
        guard let scroll = detailScroll, let document = scroll.documentView else { return }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, min(y, document.frame.height - scroll.contentSize.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    var actionForTesting: NSButton? {
        func find(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton { return button }
            return view.subviews.lazy.compactMap(find).first
        }
        return subviews.lazy.compactMap(find).first
    }
    var minimumContrastForTesting: CGFloat {
        func values(_ view: NSView) -> [CGFloat] {
            let own = (view as? NSTextField).map { [ImeAppearance.contrast($0.textColor ?? .labelColor, over: .windowBackgroundColor)] } ?? []
            return own + view.subviews.flatMap(values)
        }
        return values(self).min() ?? 100
    }

    @discardableResult
    private func label(_ text: String, in parent: NSView, x: CGFloat, y: CGFloat,
                       width: CGFloat, size: CGFloat = 11, mono: Bool = false,
                       strong: Bool = false) -> CGFloat {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = mono ? .monospacedSystemFont(ofSize: size, weight: strong ? .medium : .regular)
            : .systemFont(ofSize: size, weight: strong ? .semibold : .regular)
        label.textColor = ImeAppearance.secondaryText
        label.preferredMaxLayoutWidth = max(1, width)
        let height = max(size + 4, ceil(label.attributedStringValue.boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2)
        label.frame = NSRect(x: x, y: y, width: max(1, width), height: height)
        label.setAccessibilityLabel(text)
        parent.addSubview(label)
        return height
    }

    private func rootRow(_ roots: [WubiLearning.Root], in parent: NSView,
                         y: CGFloat, width: CGFloat) -> CGFloat {
        guard !roots.isEmpty else { return 0 }
        let cellWidth = min(52, max(32, width / CGFloat(roots.count)))
        var x: CGFloat = 0
        var rowY = y
        for root in roots {
            if x + cellWidth > width && x > 0 { x = 0; rowY += 42 }
            let column = NSView(frame: NSRect(x: x, y: rowY, width: cellWidth, height: 40))
            // Root/code are one accessible unit, preserving their correspondence.
            column.setAccessibilityElement(true)
            column.setAccessibilityRole(.group)
            column.setAccessibilityLabel("\(root.text)，键\(root.key)")
            let upper = NSTextField(labelWithString: root.text)
            upper.font = .systemFont(ofSize: root.text == "识别码" ? 11 : 15)
            upper.textColor = ImeAppearance.secondaryText
            upper.alignment = .center
            upper.frame = NSRect(x: 0, y: 18, width: cellWidth, height: 21)
            let lower = NSTextField(labelWithString: root.key)
            lower.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            lower.textColor = ImeAppearance.secondaryText
            lower.alignment = .center
            lower.frame = NSRect(x: 0, y: 1, width: cellWidth, height: 16)
            upper.setAccessibilityElement(false); lower.setAccessibilityElement(false)
            column.setAccessibilityChildren([])
            column.addSubview(upper); column.addSubview(lower)
            parent.addSubview(column)
            x += cellWidth
        }
        return rowY - y + 42
    }

    private func button(_ title: String, x: CGFloat, y: CGFloat, width: CGFloat,
                        in parent: NSView, action: Selector, tag: Int = 0) {
        let isCharacter = action == #selector(toggleCharacter(_:))
        let cacheKey = isCharacter ? "character-\(tag)" : "summary"
        let button = buttons[cacheKey] ?? NSButton()
        buttons[cacheKey] = button
        button.title = title
        button.target = self
        button.action = action
        button.isBordered = false
        button.font = .systemFont(ofSize: 11)
        button.refusesFirstResponder = true
        button.tag = tag
        button.alignment = isCharacter ? .left : .right
        let open = isCharacter ? expandedCharacters.contains(tag) : expanded
        button.image = NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityValue(open ? "已展开" : "已收起")
        button.setAccessibilityLabel(title)
        button.frame = NSRect(x: x, y: y, width: width, height: 24)
        parent.addSubview(button)
    }

    func arrange(width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        if let detailScroll { detailOrigin = detailScroll.contentView.bounds.origin }
        clearContent(dropButtons: false)
        guard let model, maxHeight >= 62 else { isHidden = true; return 0 }
        isHidden = false
        let separator = NSBox(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        separator.boxType = .separator
        addSubview(separator)
        var rule = model.rule
        if model.characters.count == 1, let item = model.characters.first {
            if let recognition = item.recognition { rule = "\(recognition.key)识别码：\(recognition.text)" }
            else if item.category == "key_name" { rule = "键名字：所在键连打四次" }
        }
        let summary = NSTextField(wrappingLabelWithString: "")
        let codeText = model.code.map { "完整码 \($0.uppercased())   " } ?? (queryUnavailable ? "学习说明暂缺" : "五笔编码暂缺")
        let text = NSMutableAttributedString(string: codeText, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: ImeAppearance.secondaryText])
        if model.code != nil { text.append(NSAttributedString(string: rule, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: ImeAppearance.secondaryText])) }
        summary.attributedStringValue = text
        summary.preferredMaxLayoutWidth = width
        let summaryHeight = ceil(text.boundingRect(with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 4
        summary.frame = NSRect(x: 0, y: 9, width: width, height: summaryHeight)
        summary.setAccessibilityLabel(text.string)
        summary.toolTip = model.rule
        summary.setAccessibilityHelp(model.rule)
        addSubview(summary)
        var y = 9 + summaryHeight + 5
        guard model.code != nil else { return min(maxHeight, y + 6) }
        if model.characters.count == 1, let item = model.characters.first {
            if !item.roots.isEmpty {
                // Recognition explanation stays in the summary, separate from real roots.
                y += rootRow(item.roots, in: self, y: y, width: width)
            }
        } else {
            let count = model.characters.count
            let indexes = count <= 3 ? Array(0..<count) : [0, 1, 2, count - 1]
            let roots: [WubiLearning.Root] = indexes.map { index in
                let item = model.characters[index]
                let length = count == 2 || (count == 3 && index == 2) ? 2 : 1
                return WubiLearning.Root(text: item.text, key: item.code.map { String($0.prefix(length)).uppercased() } ?? "?")
            }
            y += rootRow(roots, in: self, y: y, width: max(1, width - 86))
            button(expanded ? "收起逐字拆分" : "逐字拆分", x: max(0, width - 86), y: y - 32,
                width: 86, in: self, action: #selector(toggleDetails))
            if expanded {
                let scroll = NSScrollView()
                scroll.drawsBackground = false
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = true
                let document = LearningDetailsView()
                var offset: CGFloat = 0
                let inner = max(1, width - 16)
                for (index, item) in model.characters.enumerated() {
                    let open = expandedCharacters.contains(index)
                    let heading = "\(item.text)" + (open ? "" : "  \(item.code?.uppercased() ?? "编码暂缺")")
                    button(heading, x: 0, y: offset, width: inner, in: document,
                        action: #selector(toggleCharacter(_:)), tag: index)
                    offset += 27
                    if open {
                        offset += label("完整码 \(item.code?.uppercased() ?? "暂缺")   \(item.rule ?? "拆字说明暂缺")",
                            in: document, x: 12, y: offset, width: inner - 12)
                        if item.roots.isEmpty {
                            offset += label("拆字说明暂缺", in: document, x: 12, y: offset, width: inner - 12)
                        } else {
                            offset += rootRow(item.roots, in: document, y: offset, width: inner)
                        }
                        offset += 5
                    }
                }
                let height = max(0, min(137, maxHeight - y - 8))
                scroll.frame = NSRect(x: 0, y: y + 4, width: width, height: height)
                document.frame = NSRect(x: 0, y: 0, width: inner, height: offset)
                scroll.documentView = document
                addSubview(scroll)
                detailScroll = scroll
                scroll.tile()
                let origin = NSPoint(x: 0, y: max(0, min(detailOrigin.y, offset - height)))
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
                y += height + 4
            }
        }
        return min(maxHeight, y + 6)
    }

    @objc private func toggleDetails() { expanded.toggle(); onResize?() }
    @objc private func toggleCharacter(_ sender: NSButton) {
        if expandedCharacters.contains(sender.tag) { expandedCharacters.remove(sender.tag) }
        else { expandedCharacters.insert(sender.tag) }
        onResize?()
    }
    func toggleForTesting() { toggleDetails() }
    func toggleCharacterForTesting(_ index: Int) { let button = NSButton(); button.tag = index; toggleCharacter(button) }
}
private final class LearningDetailsView: NSView {
    override var isFlipped: Bool { true }
}

/// 候选窗顶部右侧的状态摘要；单字芯片，压缩到不抢候选与翻页的注意力。
struct CandidateStatus {
    var mode: String
    var english: Bool
    var fullWidth: Bool
    var traditional: Bool
    var chinesePunctuation: Bool

    /// 两字状态 + 标点符号；学习区不在这里显示（下方学习区本身就是状态）。
    var chips: [(text: String, active: Bool)] {
        [
            (mode == "wubi" ? "五笔" : mode == "pinyin" ? "拼音" : "混输", mode != "mixed"),
            (english ? "英文" : "中文", english),
            (fullWidth ? "全角" : "半角", fullWidth),
            (traditional ? "繁体" : "简体", traditional),
            (chinesePunctuation ? "。" : ".", !chinesePunctuation),
        ]
    }

    func accessibilityLabel(for text: String) -> String {
        switch text {
        case "混输", "五笔", "拼音": return "输入模式：" + text
        case "中文", "英文": return "语言：" + text
        case "全角", "半角": return "宽度：" + text
        case "简体", "繁体": return "字形：" + text
        case "。": return "标点：中文标点"
        case ".": return "标点：英文标点"
        default: return text
        }
    }
}

/// 芯片行：只读、不接收鼠标；宽度由内容决定，右对齐到翻页区左侧。
final class CandidateStateStrip: NSView {
    static let chipHeight: CGFloat = 16
    static let spacing: CGFloat = 3
    private var chips: [(text: String, active: Bool)] = []
    private let labels = (0..<6).map { _ in NSTextField(labelWithString: "") }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in labels {
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.alignment = .center
            label.usesSingleLineMode = true
            label.lineBreakMode = .byClipping
            label.wantsLayer = true
            label.layer?.cornerRadius = 5
            label.layer?.actions = ["backgroundColor": NSNull()]
            label.isHidden = true
            addSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func update(_ status: CandidateStatus) {
        chips = status.chips
        for (index, label) in labels.enumerated() {
            guard index < chips.count else {
                label.isHidden = true
                continue
            }
            let chip = chips[index]
            label.stringValue = chip.text
            label.isHidden = false
            label.setAccessibilityElement(true)
            label.setAccessibilityRole(.staticText)
            label.setAccessibilityLabel(status.accessibilityLabel(for: chip.text))
            label.toolTip = label.accessibilityLabel()
        }
        layoutChips()
    }

    var preferredWidth: CGFloat {
        chips.reduce(0) { $0 + chipWidth($1.text) } + CGFloat(max(0, chips.count - 1)) * Self.spacing
    }

    private func chipWidth(_ text: String) -> CGFloat {
        ceil((text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width) + 12
    }

    private func layoutChips() {
        var x: CGFloat = 0
        for (index, chip) in chips.enumerated() {
            let width = chipWidth(chip.text)
            labels[index].frame = NSRect(x: x, y: 0, width: width, height: Self.chipHeight)
            x += width + Self.spacing
        }
    }

    func paint(for appearance: NSAppearance) {
        appearance.performAsCurrentDrawingAppearance {
            for (index, label) in labels.enumerated() where index < chips.count {
                let active = chips[index].active
                label.textColor = active ? .labelColor : ImeAppearance.secondaryText
                label.layer?.backgroundColor = active
                    ? NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
                    : NSColor.clear.cgColor
            }
        }
    }

    var chipTextsForTesting: [String] { chips.map(\.text) }
    var chipFramesForTesting: [NSRect] { labels.prefix(chips.count).map(\.frame) }
}

final class CandidateWindow: NSObject {
    private let panel: CandidatePanel
    private let inputLabel = NSTextField(labelWithString: "")
    private let learningView = WubiLearningView()
    private var learningAnchor: (NSRect, NSRect)?
    private let pageLabel = NSTextField(labelWithString: "")
    private let stateStrip = CandidateStateStrip()
    private var status: CandidateStatus?
    private let hintLabel = NSTextField(labelWithString: "")
    private let warningLabel = NSTextField(labelWithString: "")
    private let previousButton = CandidatePageButton()
    private let nextButton = CandidatePageButton()
    private let scrollView = NSScrollView()
    private let document = CandidateDocument()
    private var labels: [CandidateLabel] = []
    private var renderedCount = 0
    private var pageIndex = 0
    private var pageCount = 0
    private var selectedIndex = 0
    private var themeTimer: Timer?
    private var available = NSSize(width: 640, height: 800)
    private var input = ""
    private var hint: String?
    private var showsNavigationHint = false
    private(set) var isVertical = false
    private var warning: String?

    var navigationHint: String { "\(isVertical ? "↑↓" : "←→")浏览 · 空格确认 · 数字直选" }

    /// Use the axis of the last rendered layout, shared by preview and IMK.
    func navigationDelta(for event: NSEvent) -> Int? {
        guard event.type == .keyDown,
            event.modifierFlags.intersection([.command, .control, .option]).isEmpty
        else { return nil }
        switch event.keyCode {
        case isVertical ? 126 : 123: return -1
        case isVertical ? 125 : 124: return 1
        default: return nil
        }
    }

    var onSelect: ((Int) -> Void)?
    var onPage: ((Int) -> Void)?
    var frame: NSRect { panel.frame }
    var isVisible: Bool { panel.isVisible }
    func updateStatus(_ status: CandidateStatus) {
        self.status = status
        stateStrip.update(status)
        arrange()
    }
    /// 芯片数量/宽度变化后按最近一次光标与屏幕重新定位。
    func refreshLayout() {
        guard let (caret, area) = learningAnchor else { return }
        layout(at: caret, within: area)
    }
    var stateChipsForTesting: [String] { stateStrip.chipTextsForTesting }
    var stateStripFrameForTesting: NSRect { stateStrip.frame }
    var inputFrameForTesting: NSRect { inputLabel.frame }
    var displayedInput: String { inputLabel.stringValue }
    var displayedHintForTesting: String { hintLabel.stringValue }
    var displayedWarning: String? { warningLabel.isHidden ? nil : warningLabel.stringValue }
    var displayedCandidateTexts: [String] { labels.prefix(renderedCount).map(\.stringValue) }
    var candidateAccessibilityLabelsForTesting: [String] { labels.prefix(renderedCount).map { $0.accessibilityLabel() ?? "" } }
    var configuredAppearanceForTesting: NSAppearance.Name? { panel.appearance?.name }
    var pageStateForTesting: (visible: Bool, previous: Bool, next: Bool, text: String) {
        (!pageLabel.isHidden, previousButton.isEnabled, nextButton.isEnabled, pageLabel.stringValue)
    }
    var selectedCandidateIndexForTesting: Int { selectedIndex }
    var keyboardSelectedCandidatesForTesting: [Int] {
        labels.prefix(renderedCount).enumerated().compactMap { $0.element.isKeyboardSelected ? $0.offset : nil }
    }
    var pageFramesForTesting: [NSRect] { [previousButton.frame, pageLabel.frame, nextButton.frame] }
    var scrollingForTesting: Bool { scrollView.hasVerticalScroller }
    var permitsKeyboardFocusForTesting: Bool { panel.canBecomeKey || panel.canBecomeMain }
    func candidateFontForTesting(at index: Int) -> NSFont? {
        guard index >= 0, index < renderedCount else { return nil }
        return labels[index].attributedStringValue.attribute(.font, at: labels[index].attributedStringValue.length - 1, effectiveRange: nil) as? NSFont
    }

    override init() {
        panel = CandidatePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 8
        container.layer?.borderWidth = 1
        container.layer?.actions = ["backgroundColor": NSNull(), "borderColor": NSNull()]
        panel.contentView = container
        for field in [inputLabel, pageLabel, hintLabel, warningLabel] {
            field.usesSingleLineMode = true
            field.lineBreakMode = .byTruncatingMiddle
            container.addSubview(field)
        }
        container.addSubview(stateStrip)
        inputLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        inputLabel.textColor = .labelColor
        inputLabel.setAccessibilityLabel("输入编码")
        pageLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        pageLabel.alignment = .center
        pageLabel.textColor = ImeAppearance.secondaryText
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = ImeAppearance.secondaryText
        warningLabel.font = .systemFont(ofSize: 11)
        warningLabel.textColor = ImeAppearance.errorText
        for (button, symbol, title, action) in [
            (previousButton, "chevron.left", "上一页", #selector(previousPage)),
            (nextButton, "chevron.right", "下一页", #selector(nextPage)),
        ] {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 12.5, weight: .medium))
            button.title = button.image == nil ? title : ""
            button.isBordered = false
            button.refusesFirstResponder = true
            button.controlSize = .small
            button.target = self
            button.action = action
            button.setAccessibilityLabel(title)
            container.addSubview(button)
        }
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.setAccessibilityHelp("内容较长时可滚动查看全部候选，数字序号保持不变")
        scrollView.documentView = document
        document.setAccessibilityRole(.group)
        document.setAccessibilityLabel("候选字词")
        container.addSubview(scrollView)
        container.addSubview(learningView)
        learningView.onResize = { [weak self] in
            guard let self, let anchor = self.learningAnchor else { return }
            self.layout(at: anchor.0, within: anchor.1)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        // Warm native Chinese font layout without showing a window.
        update(candidates: [ImeCandidate(text: "萤火虫", code: "", source: .codeTable, isPrefix: false)])
        update(candidates: [])
    }

    deinit { themeTimer?.invalidate(); NSWorkspace.shared.notificationCenter.removeObserver(self) }
    @objc private func displayOptionsChanged() { refreshAppearance() }

    private func startThemeTimer() {
        guard themeTimer == nil else { return }
        themeTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshAppearance()
        }
    }

    func refreshAppearance() {
        ImeAppearance.applyTheme(to: panel)
        paintResolvedAppearance()
    }
    func setAppearanceForTesting(_ appearance: NSAppearance) {
        panel.appearance = appearance
        paintResolvedAppearance()
    }
    private func paintResolvedAppearance() {
        panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            panel.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            panel.contentView?.layer?.borderColor = ImeAppearance.candidateBorderColor(highContrast: ImeAppearance.isHighContrast(panel.effectiveAppearance)).cgColor
            for label in labels.prefix(renderedCount) where label.isHovered {
                label.refreshSelectionAppearance()
            }
            for label in labels.prefix(renderedCount) where !label.isHovered {
                label.refreshSelectionAppearance()
            }
            stateStrip.paint(for: panel.effectiveAppearance)
        }
    }

    private static func render(index: Int, selected: Bool, _ candidate: ImeCandidate) -> NSAttributedString {
        let number = "\(index + 1)"
        let weight: NSFont.Weight = selected ? .semibold : .regular
        let ordinalFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: weight)
        let text = NSMutableAttributedString(string: number, attributes: [
            .font: ordinalFont,
            .foregroundColor: ImeAppearance.secondaryText,
        ])
        let prefixWidth = ((number + " ") as NSString).size(withAttributes: [.font: ordinalFont]).width
        text.append(NSAttributedString(string: " ", attributes: [.font: ordinalFont,
            .kern: max(0, 20 - prefixWidth), .foregroundColor: ImeAppearance.secondaryText]))
        text.append(NSAttributedString(string: CandidateTextPresentation.display(candidate.text, font: .systemFont(ofSize: 17, weight: weight)), attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]))
        return text
    }

    func update(candidates: [ImeCandidate], pageIndex: Int = 0, pageCount: Int = 1,
                selectedIndex: Int = 0,
                input: String = "", hint: String? = nil, showsNavigationHint: Bool = false,
                warning: String? = nil) {
        refreshAppearance()
        self.input = candidates.isEmpty ? "" : input
        self.hint = candidates.isEmpty ? nil : hint
        self.showsNavigationHint = !candidates.isEmpty && showsNavigationHint
        self.warning = candidates.isEmpty ? nil : warning
        self.pageCount = candidates.isEmpty ? 0 : max(1, pageCount)
        self.pageIndex = min(max(0, pageIndex), max(0, self.pageCount - 1))
        self.selectedIndex = candidates.isEmpty ? 0 : min(max(0, selectedIndex), candidates.count - 1)
        learningView.update(ImeConfig.bool("candidate.show_wubi_learning") && !candidates.isEmpty
            ? candidates[self.selectedIndex].text : nil)
        inputLabel.stringValue = self.input
        inputLabel.toolTip = self.input
        inputLabel.setAccessibilityValue(self.input)
        hintLabel.stringValue = self.hint ?? ""
        hintLabel.toolTip = self.hint
        hintLabel.setAccessibilityLabel(self.hint)
        warningLabel.stringValue = self.warning == nil ? "" : "繁体不可用，当前简体"
        warningLabel.toolTip = self.warning
        warningLabel.setAccessibilityLabel(self.warning)
        pageLabel.stringValue = self.pageCount > 1 ? "\(self.pageIndex + 1)/\(self.pageCount)" : ""
        pageLabel.setAccessibilityLabel("第\(self.pageIndex + 1)页，共\(self.pageCount)页")
        for label in labels {
            label.onClick = nil
            label.setAccessibilityElement(false)
            label.isHidden = true
        }
        for (index, candidate) in candidates.enumerated() {
            if index == labels.count {
                let label = CandidateLabel(labelWithString: "")
                label.cell = PaddedCandidateCell(textCell: "")
                label.isEditable = false
                label.isBordered = false
                label.drawsBackground = false
                label.alignment = .left
                labels.append(label)
                document.addSubview(label)
            }
            let label = labels[index]
            label.isHidden = false
            let selected = index == self.selectedIndex
            label.font = .systemFont(ofSize: 17, weight: selected ? .semibold : .regular)
            label.attributedStringValue = Self.render(index: index, selected: selected, candidate)
            let visibleText = CandidateTextPresentation.display(candidate.text, font: label.font ?? .systemFont(ofSize: 17))
            let missing = visibleText != candidate.text
            let detail = missing ? "系统字体缺字；选择仍输入原字符" : candidate.source.label
            label.toolTip = "\(visibleText) · \(detail)"
            label.setAccessibilityElement(true)
            label.setAccessibilityLabel("第\(index + 1)项，\(visibleText)，\(candidate.source.label)\(missing ? "，" + detail : "")\(selected ? "，键盘焦点" : "")\(index == 0 ? "，首选" : "")")
            label.onClick = { [weak self] in self?.onSelect?(index) }
            label.setKeyboardSelected(selected)
            label.setHovered(false)
        }
        renderedCount = candidates.count
        arrange()
    }

    @objc private func previousPage() {
        guard pageCount > 1, pageIndex > 0 else { return }
        onPage?(-1)
    }
    @objc private func nextPage() {
        guard pageCount > 1, pageIndex + 1 < pageCount else { return }
        onPage?(1)
    }

    private func arrange() {
        let margin: CGFloat = 16
        let maxWidth = max(1, min(640, available.width))
        let innerLimit = max(1, maxWidth - margin * 2)
        let visible = Array(labels.prefix(renderedCount))
        let widths = visible.map { ceil($0.attributedStringValue.size().width) + 2 * PaddedCandidateCell.horizontal + 2 }
        let horizontalWidth = widths.reduce(0, +) + CGFloat(max(0, renderedCount - 1)) * 14
        let vertical = horizontalWidth > innerLimit
        isVertical = vertical
        let displayedHint = showsNavigationHint ? navigationHint : hint
        hintLabel.stringValue = displayedHint ?? ""
        hintLabel.toolTip = displayedHint
        hintLabel.setAccessibilityLabel(displayedHint)
        let pagesVisible = renderedCount > 0 && pageCount > 1
        let pageSize = pageLabel.cell?.cellSize ?? pageLabel.intrinsicContentSize
        let pageWidth = ceil(pageSize.width)
        let navigationWidth: CGFloat = pagesVisible ? pageWidth + 56 : 0
        let headerVisible = !input.isEmpty || pagesVisible
        let statusVisible = headerVisible && status != nil
        let statusWidth = statusVisible ? stateStrip.preferredWidth : 0
        let reservedHeader = navigationWidth + (statusVisible ? statusWidth + 8 : 0)
        let inputWidth = ceil((input as NSString).size(withAttributes: [.font: inputLabel.font ?? .monospacedSystemFont(ofSize: 12, weight: .regular)]).width) + 4
        let hintWidth = ceil((hintLabel.stringValue as NSString).size(withAttributes: [.font: hintLabel.font ?? .systemFont(ofSize: 11)]).width) + 4
        let warningWidth = warning == nil ? 0 : ceil(warningLabel.intrinsicContentSize.width)
        let naturalWidth = max(horizontalWidth, inputWidth + reservedHeader + 8, hintWidth, warningWidth, max(0, min(400, maxWidth) - margin * 2))
        let width = min(maxWidth, max(54, (vertical ? innerLimit : naturalWidth) + margin * 2))
        let inner = max(1, width - margin * 2)
        let headerHeight: CGFloat = headerVisible ? 26 : 0
        let hintHeight: CGFloat = displayedHint?.isEmpty == false ? 18 : 0
        let warningHeight: CGFloat = warning == nil ? 0 : 18
        // 只有真的要显示附行/警告时才保留底部 22pt 区（hint 下留 8pt 边距）；
        // 否则底部只留 10pt，避免窗口比内容“多出”一大截、整体显得上移（报告 073）。
        let bottomReserve: CGFloat = (hintHeight + warningHeight) > 0 ? 22 : 12
        let baseExtra = CGFloat(headerVisible ? bottomReserve : 16) + headerHeight + hintHeight + warningHeight + (headerVisible ? 6 : 0)
        func heights(for bodyWidth: CGFloat) -> [CGFloat] {
            visible.map { label in
                if !vertical {
                    return ceil(label.attributedStringValue.size().height) + 2 * PaddedCandidateCell.vertical + 2
                }
                return ceil(label.attributedStringValue.boundingRect(with: NSSize(width: max(1, bodyWidth - 2 * PaddedCandidateCell.horizontal), height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2 * PaddedCandidateCell.vertical + 2
            }
        }
        var bodyWidth = inner
        var rowHeights = heights(for: bodyWidth)
        func totalHeight() -> CGFloat {
            vertical ? rowHeights.reduce(0, +) + CGFloat(max(0, renderedCount - 1)) * 8 : (rowHeights.max() ?? 0)
        }
        var naturalHeight = totalHeight()
        let preferredBody = min(naturalHeight, max(1, min(320, available.height - baseExtra)))
        let learningBudget = min(270, max(0, available.height - baseExtra - preferredBody - 8))
        let learningHeight = learningView.arrange(width: inner, maxHeight: learningBudget)
        let extraHeight = baseExtra + learningHeight + (learningHeight > 0 ? 8 : 0)
        let maxBody = max(1, min(320, available.height - extraHeight))
        scrollView.hasVerticalScroller = naturalHeight > maxBody
        if scrollView.hasVerticalScroller {
            bodyWidth = max(1, inner - NSScroller.scrollerWidth(for: .small, scrollerStyle: scrollView.scrollerStyle))
            rowHeights = heights(for: bodyWidth)
            naturalHeight = totalHeight()
        }
        let bodyHeight = min(maxBody, naturalHeight)
        let total = max(32, min(available.height, bodyHeight + extraHeight))
        panel.setContentSize(NSSize(width: width, height: total))
        let top = total - 8
        inputLabel.isHidden = !headerVisible
        pageLabel.isHidden = !pagesVisible
        previousButton.isHidden = !pagesVisible
        nextButton.isHidden = !pagesVisible
        previousButton.isEnabled = pagesVisible && pageIndex > 0
        nextButton.isEnabled = pagesVisible && pageIndex + 1 < pageCount
        let navigationCenterY = top - headerHeight / 2
        inputLabel.frame = NSRect(x: margin, y: navigationCenterY - 10,
            width: max(1, inner - reservedHeader - (pagesVisible ? 8 : 0)), height: 20)
        let pageHeight = ceil(pageSize.height)
        // 光学对齐：数字/雪佛龙的墨迹比汉字矮，基线相同仍显低；整体上提 1.5pt。
        let pagerOpticalLift: CGFloat = 1.5
        nextButton.frame = NSRect(x: width - margin - 24,
            y: navigationCenterY - 12 + pagerOpticalLift, width: 24, height: 24)
        pageLabel.frame = NSRect(x: nextButton.frame.minX - pageWidth - 4,
            y: navigationCenterY - pageHeight / 2 + pagerOpticalLift,
            width: pageWidth, height: pageHeight)
        previousButton.frame = NSRect(x: pageLabel.frame.minX - 28,
            y: navigationCenterY - 12 + pagerOpticalLift, width: 24, height: 24)
        stateStrip.isHidden = !statusVisible
        if statusVisible {
            let right = (pagesVisible ? previousButton.frame.minX : width - margin) - 8
            stateStrip.frame = NSRect(x: max(margin, right - statusWidth),
                y: navigationCenterY - CandidateStateStrip.chipHeight / 2,
                width: statusWidth, height: CandidateStateStrip.chipHeight)
        }
        let bodyTop = top - headerHeight - 2
        scrollView.frame = NSRect(x: margin, y: bodyTop - bodyHeight, width: inner, height: bodyHeight)
        scrollView.tile()
        document.frame = NSRect(x: 0, y: 0, width: max(bodyWidth, scrollView.contentSize.width), height: naturalHeight)
        let pitch = renderedCount > 0 ? (inner + 8) / CGFloat(renderedCount) : 0
        let equalColumns = !vertical && (widths.max() ?? 0) <= pitch - 8
        var offset: CGFloat = 0
        for (index, label) in visible.enumerated() {
            label.usesSingleLineMode = !vertical
            label.lineBreakMode = vertical ? .byWordWrapping : .byClipping
            label.cell?.wraps = vertical
            label.preferredMaxLayoutWidth = bodyWidth
            label.frame = vertical
                ? NSRect(x: 0, y: offset, width: bodyWidth, height: rowHeights[index])
                : NSRect(x: offset, y: 0, width: equalColumns ? pitch - 8 : widths[index], height: rowHeights[index])
            offset += vertical ? rowHeights[index] + 8 : equalColumns ? pitch : widths[index] + 14
        }
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        hintLabel.isHidden = hintHeight == 0
        warningLabel.isHidden = warningHeight == 0
        warningLabel.frame = NSRect(x: margin, y: 8 + hintHeight, width: inner, height: warningHeight)
        hintLabel.frame = NSRect(x: margin, y: 8, width: inner, height: hintHeight)
        learningView.frame = NSRect(x: margin, y: 8 + hintHeight + warningHeight, width: inner, height: learningHeight)
    }

    var learningVisibleForTesting: Bool { !learningView.isHidden }
    var learningDetailsExpandedForTesting: Bool { learningView.expandedForTesting }
    var learningSummaryForTesting: String {
        learningView.subviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")
    }
    var learningActionForTesting: NSButton? { learningView.actionForTesting }
    var candidateViewportForTesting: NSSize { scrollView.frame.size }
    var candidateViewportFrameForTesting: NSRect { scrollView.frame }
    var learningScrollOriginForTesting: NSPoint { learningView.detailOriginForTesting }
    func scrollLearningForTesting(_ y: CGFloat) { learningView.scrollDetailsForTesting(y) }
    var learningTextContrastForTesting: CGFloat {
        var value: CGFloat = 100
        panel.effectiveAppearance.performAsCurrentDrawingAppearance { value = learningView.minimumContrastForTesting }
        return value
    }
    func toggleLearningDetailsForTesting() { learningView.toggleForTesting() }
    func toggleLearningCharacterForTesting(_ index: Int) { learningView.toggleCharacterForTesting(index) }
    func simulateClick(at index: Int) {
        guard index >= 0, index < renderedCount else { return }
        onSelect?(index)
    }
    func accessiblePressForTesting(at index: Int) -> Bool {
        guard index >= 0, index < labels.count else { return false }
        return labels[index].accessibilityPerformPress()
    }
    func pagePressForTesting(_ delta: Int) -> Bool {
        (delta < 0 ? previousButton : nextButton).accessibilityPerformPress()
    }
    func simulateHover(at index: Int, _ hovered: Bool) {
        guard index >= 0, index < renderedCount else { return }
        labels[index].setHovered(hovered)
    }
    func isHovered(at index: Int) -> Bool {
        index >= 0 && index < renderedCount && labels[index].isHovered
    }
    func isHoverRenderable(at index: Int) -> Bool {
        index >= 0 && index < renderedCount && labels[index].wantsLayer
    }
    func layoutForTesting() -> (container: NSRect, labels: [NSRect])? {
        guard let container = panel.contentView else { return nil }
        return (container.bounds, labels.prefix(renderedCount).map { $0.convert($0.bounds, to: container) })
    }
    func renderSnapshotForTesting() -> NSBitmapImageRep? {
        guard let view = panel.contentView, view.bounds.width > 1, view.bounds.height > 1,
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.layoutSubtreeIfNeeded()
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    static func bestScreenIndex(for caret: NSRect, among frames: [NSRect]) -> Int? {
        guard !frames.isEmpty else { return nil }
        var bestIndex: Int?
        var bestOverlap: CGFloat = 0
        for (index, frame) in frames.enumerated() where frame.intersects(caret) {
            let overlap = frame.intersection(caret)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if bestIndex == nil || area > bestOverlap { bestIndex = index; bestOverlap = area }
        }
        if let bestIndex { return bestIndex }
        let center = NSPoint(x: caret.midX, y: caret.midY)
        return frames.firstIndex { $0.contains(center) } ?? 0
    }
    func show(at caret: NSRect) {
        refreshAppearance()
        if themeTimer == nil { startThemeTimer() }
        let screens = NSScreen.screens
        let index = Self.bestScreenIndex(for: caret, among: screens.map(\.frame))
        let screen = index.flatMap { $0 < screens.count ? screens[$0] : nil } ?? NSScreen.main
        layout(at: caret, within: screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080))
        panel.orderFront(nil)
    }
    func layout(at caret: NSRect, within area: NSRect) {
        learningAnchor = (caret, area)
        available = area.size
        arrange()
        let size = panel.frame.size
        let x = max(area.minX, min(caret.minX, area.maxX - size.width))
        let preferred = caret.maxY + 4
        let y = preferred + size.height <= area.maxY ? preferred : caret.minY - size.height - 4
        panel.setFrameOrigin(NSPoint(x: x, y: max(area.minY, min(y, area.maxY - size.height))))
    }
    func hide() {
        themeTimer?.invalidate()
        themeTimer = nil
        panel.orderOut(nil)
        update(candidates: [])
    }
}
