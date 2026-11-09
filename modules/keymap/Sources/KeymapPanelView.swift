import AppKit

/// 自包含的键位图面板：方案名 + 键位图 + 口诀开关 + 口诀文本。
///
/// 面板自己管口诀的显隐与高度，宿主只需要给宽度、决定是否显示面板；
/// 这样这块区域可以直接搬到其它窗口或项目里复用。
final class KeymapPanelView: NSView {
    static let headerHeight: CGFloat = 20
    static let headerGap: CGFloat = 10
    static let mnemonicGap: CGFloat = 10

    let map: KeyboardMapView
    private let schemeLabel = NSTextField(labelWithString: "")
    private let mnemonicLabel = NSTextField(labelWithString: "")
    private let mnemonicSwitch = NSSwitch()
    private let mnemonicTitle = NSTextField(labelWithString: "口诀")

    /// 口诀显隐（面板内部状态）。
    var showsMnemonics: Bool {
        get { mnemonicSwitch.state == .on }
        set { mnemonicSwitch.state = newValue ? .on : .off; applyMnemonicVisibility() }
    }

    override var isFlipped: Bool { true }

    init(layout: KeyRootLayout) {
        map = KeyboardMapView(layout: layout)
        super.init(frame: .zero)
        schemeLabel.stringValue = "\(layout.displayName) · 25 键字根分布"
        schemeLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        schemeLabel.textColor = .secondaryLabelColor
        addSubview(schemeLabel)

        addSubview(map)

        mnemonicSwitch.target = self
        mnemonicSwitch.action = #selector(toggleMnemonics)
        mnemonicSwitch.state = .off
        mnemonicSwitch.controlSize = .small
        mnemonicSwitch.toolTip = "显示五个区的助记口诀"
        mnemonicSwitch.setAccessibilityLabel("口诀")
        addSubview(mnemonicSwitch)

        mnemonicTitle.font = .systemFont(ofSize: 11)
        mnemonicTitle.textColor = .secondaryLabelColor
        addSubview(mnemonicTitle)


        mnemonicLabel.maximumNumberOfLines = 0
        mnemonicLabel.cell?.wraps = true
        mnemonicLabel.font = .systemFont(ofSize: 10.5)
        mnemonicLabel.textColor = .secondaryLabelColor
        mnemonicLabel.setAccessibilityLabel("五笔助记口诀")
        mnemonicLabel.isHidden = true
        addSubview(mnemonicLabel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func toggleMnemonics() {
        applyMnemonicVisibility()
        needsLayout = true
        // 高度变了，交给宿主重新排版（面板只报告期望高度）。
        onHeightChange?()
    }

    /// 口诀显隐变化后通知宿主重新布局。
    var onHeightChange: (() -> Void)?

    private func applyMnemonicVisibility() {
        mnemonicLabel.isHidden = !showsMnemonics
        needsLayout = true
    }

    private func mnemonicText(width: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 58)]
        style.headIndent = 58
        style.firstLineHeadIndent = 2
        style.lineSpacing = 4
        return NSAttributedString(
            string: map.layout.mnemonicsByZone
                .map { "\($0.name)\t\($0.text)" }.joined(separator: "\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 10.5),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: style])
    }

    /// 面板在给定宽度下的期望高度（宿主据此排版）。
    func height(forWidth width: CGFloat) -> CGFloat {
        var total = Self.headerHeight + Self.headerGap + KeyboardMapView.totalHeight
        if showsMnemonics {
            total += Self.mnemonicGap + mnemonicHeight(width: width)
        }
        return total
    }

    func mnemonicHeight(width: CGFloat) -> CGFloat {
        let bounds = mnemonicText(width: width).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height) + 6
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        // 头部三项按中线对齐：文字用 14pt 行高，开关按自身高度居中。
        let textHeight: CGFloat = 14
        let textY = (Self.headerHeight - textHeight) / 2
        let switchHeight: CGFloat = 16
        let switchY = (Self.headerHeight - switchHeight) / 2
        schemeLabel.frame = NSRect(x: 2, y: textY, width: max(0, width - 120), height: textHeight)
        mnemonicSwitch.frame = NSRect(x: width - 36, y: switchY, width: 36, height: switchHeight)
        mnemonicTitle.frame = NSRect(x: width - 36 - 8 - 24, y: textY, width: 24, height: textHeight)
        map.frame = NSRect(x: 0, y: Self.headerHeight + Self.headerGap, width: width,
                           height: KeyboardMapView.totalHeight)
        if showsMnemonics {
            mnemonicLabel.frame = NSRect(x: 0, y: map.frame.maxY + Self.mnemonicGap,
                                         width: width, height: mnemonicHeight(width: width - 2))
            mnemonicLabel.attributedStringValue = mnemonicText(width: width - 2)
        }
    }
}
