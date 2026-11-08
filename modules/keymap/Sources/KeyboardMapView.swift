import AppKit

/// 可复用的编码方案键位图：QWERTY 物理排布，每键显示该方案的键名字根与全部字根。
///
/// - 用户敲键时对应键位点亮（`flash`），答完后把答案用到的键位持久描边（`markAnswer`）。
/// - 只依赖 AppKit + `KeyRootLayout`，不依赖任何输入法类型，可整份复制到其他项目复用。
final class KeyboardMapView: NSView {
    let layout: KeyRootLayout

    static let keyHeight: CGFloat = 42
    static let rowGap: CGFloat = 4
    static var totalHeight: CGFloat { keyHeight * 3 + rowGap * 2 }

    private var pressed: Character?
    private var answerKeys: Set<Character> = []

    init(layout: KeyRootLayout = .wubi86) {
        self.layout = layout
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(layout.displayName) 字根键位图")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var entries: [Character: KeyRootLayout.Entry] { layout.entries }
    var schemeID: String { layout.schemeID }
    var pressedLetterForTesting: String? { pressed.map(String.init) }
    var markedLettersForTesting: Set<Character> { answerKeys }

    override var isFlipped: Bool { true }

    /// 敲键时的瞬时点亮。
    func flash(_ letter: Character) {
        pressed = letter.uppercased().first
        needsDisplay = true
    }

    func clearFlash() {
        pressed = nil
        needsDisplay = true
    }

    /// 答完后把答案用到的键位持久描边；传空串清除。
    func markAnswer(_ code: String) {
        answerKeys = Set(code.uppercased().compactMap { $0 })
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let gap: CGFloat = 3.5
        let keyWidth = (bounds.width - gap * 9) / 10
        for (rowIndex, row) in layout.rows.enumerated() {
            let indent = CGFloat(rowIndex) * (keyWidth + gap) * 0.35
            let y = CGFloat(rowIndex) * (Self.keyHeight + Self.rowGap)
            for (index, letter) in row.enumerated() {
                let rect = NSRect(x: indent + CGFloat(index) * (keyWidth + gap), y: y,
                                  width: keyWidth, height: Self.keyHeight)
                drawKey(letter: letter, in: rect)
            }
        }
    }

    private func drawKey(letter: Character, in rect: NSRect) {
        let entry = layout.entries[letter]
        let isPressed = pressed == letter
        let isAnswer = answerKeys.contains(letter)
        let tint = Self.zoneColor(entry?.zone ?? 0)
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        (isPressed ? tint.withAlphaComponent(0.9) : tint.withAlphaComponent(0.12)).setFill()
        path.fill()
        if isAnswer && !isPressed {
            tint.withAlphaComponent(0.95).setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        let keyNameColor: NSColor = isPressed ? .white : .labelColor
        let rootColor: NSColor = isPressed ? NSColor.white.withAlphaComponent(0.92) : .secondaryLabelColor
        drawText(entry?.keyName ?? "", font: .systemFont(ofSize: 12.5, weight: .semibold), color: keyNameColor,
                 in: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: 15))
        drawRoots(entry?.roots ?? [], in: rect, color: rootColor)
        drawText(String(letter), font: .monospacedSystemFont(ofSize: 7.5, weight: .medium),
                 color: isPressed ? NSColor.white.withAlphaComponent(0.85) : .tertiaryLabelColor,
                 in: NSRect(x: rect.minX, y: rect.maxY - 10, width: rect.width, height: 9))
    }

    /// 字根按 3 列铺排，超过 9 个时用省略号收尾（练手够用，完整表见方案文档）。
    private func drawRoots(_ roots: [String], in rect: NSRect, color: NSColor) {
        guard !roots.isEmpty else { return }
        let columns = 3
        let lineHeight: CGFloat = 8.2
        let cellWidth = rect.width / CGFloat(columns)
        let available = rect.height - 15 - 8
        let maxLines = max(1, Int(available / lineHeight))
        let capacity = columns * maxLines
        var shown = Array(roots.prefix(capacity))
        if roots.count > capacity, !shown.isEmpty { shown[shown.count - 1] = "…" }
        for (index, root) in shown.enumerated() {
            let column = index % columns
            let line = index / columns
            let cell = NSRect(x: rect.minX + CGFloat(column) * cellWidth,
                              y: rect.minY + 16 + CGFloat(line) * lineHeight,
                              width: cellWidth, height: lineHeight + 1.5)
            drawText(root, font: .systemFont(ofSize: 7.5), color: color, in: cell)
        }
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph]).draw(in: rect)
    }

    private static func zoneColor(_ zone: Int) -> NSColor {
        switch zone {
        case 1: return .systemGreen
        case 2: return .systemBlue
        case 3: return .systemOrange
        case 4: return .systemPurple
        case 5: return .systemPink
        default: return .systemGray
        }
    }

    func accessibilitySummary() -> String {
        "\(layout.displayName) 字根键位图：" + layout.entries.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.keyName)" }.joined(separator: "，")
    }
}
