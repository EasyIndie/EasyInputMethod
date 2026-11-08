import AppKit

/// 可复用的编码方案键位图：QWERTY 物理排布，每键显示该方案的键名字根与全部字根。
///
/// - 用户敲键时对应键位点亮（`flash`），答完后把答案用到的键位持久描边（`markAnswer`）。
/// - 只依赖 AppKit + `KeyRootLayout`，不依赖任何输入法类型，可整份复制到其他项目复用。
final class KeyboardMapView: NSView {
    let layout: KeyRootLayout

    static let keyHeight: CGFloat = 72
    static let keyGap: CGFloat = 5
    static let rowGap: CGFloat = 5
    static var totalHeight: CGFloat { keyHeight * 3 + rowGap * 2 }
    /// 字根网格：5 列 × 3 行（每键最多显示 15 个，超出以省略号收尾）。
    static let rootColumns = 5
    static let rootRows = 3

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
        let gap = Self.keyGap
        let keyWidth = (bounds.width - gap * 9) / 10
        // 真实键盘的错位：第二排右移约 1/4 键宽，第三排约 5/8 键宽。
        let indents: [CGFloat] = [0, 0.28, 0.62]
        for (rowIndex, row) in layout.rows.enumerated() {
            let indent = indents[min(rowIndex, indents.count - 1)] * (keyWidth + gap)
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
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        // 字母突出：左上角大号加粗
        drawText(String(letter), font: .monospacedSystemFont(ofSize: 13, weight: .bold),
                 color: isPressed ? .white : .labelColor,
                 in: NSRect(x: rect.minX + 5, y: rect.minY + 2, width: rect.width - 8, height: 16),
                 alignment: .left)
        drawText(entry?.keyName ?? "", font: .systemFont(ofSize: 14.5, weight: .semibold), color: keyNameColor,
                 in: NSRect(x: rect.minX, y: rect.minY + 17, width: rect.width, height: 18))
        drawRoots(entry?.roots ?? [], in: rect, color: rootColor)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 只显示能稳定渲染成汉字的字根。
    ///
    /// 语料里的键位字根混有康熙部首（⺈ ⺝）、注音符号（ㄅ ㄠ）、日文片假名部件（リ）以及扩展区生僻码位，
    /// 这些在系统字体里没有字形，直接画会变成 `?`。这里按"是否为 CJK 汉字/部件"筛掉，
    /// 而不是依赖字体探测——字体探测在无 GUI 的测试进程里不可靠。
    static func displayableRoots(_ roots: [String]) -> [String] {
        roots.filter { root in
            root.unicodeScalars.allSatisfy { scalar in
                switch scalar.value {
                case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0xF900...0xFAFF: return true
                default: return false
                }
            }
        }
    }

    /// 网格能容纳的字根（超出部分以省略号收尾）。
    static func visibleRoots(_ roots: [String]) -> [String] {
        let capacity = rootColumns * rootRows
        let usable = displayableRoots(roots)
        guard usable.count > capacity else { return usable }
        return Array(usable.prefix(capacity - 1)) + ["…"]
    }

    private func drawRoots(_ roots: [String], in rect: NSRect, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 8)
        let shown = Self.visibleRoots(roots)
        guard !shown.isEmpty else { return }
        let columns = Self.rootColumns
        let top: CGFloat = 34
        let lineHeight = (rect.height - top - 2) / CGFloat(Self.rootRows)
        let cellWidth = rect.width / CGFloat(columns)
        for (index, root) in shown.enumerated() {
            let column = index % columns
            let line = index / columns
            let cell = NSRect(x: rect.minX + CGFloat(column) * cellWidth,
                              y: rect.minY + top + CGFloat(line) * lineHeight,
                              width: cellWidth, height: lineHeight)
            drawText(root, font: font, color: color, in: cell)
        }
    }

    private func drawText(_ text: String, font: NSFont, color: NSColor, in rect: NSRect,
                          alignment: NSTextAlignment = .center) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
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
