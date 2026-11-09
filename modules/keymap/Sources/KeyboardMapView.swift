import AppKit

/// 可复用的编码方案键位图：QWERTY 物理排布，每键显示该方案的键名字根与全部字根。
///
/// - 用户敲键时对应键位点亮（`flash`），答完后把答案用到的键位持久描边（`markAnswer`）。
/// - 只依赖 AppKit + `KeyRootLayout`，不依赖任何输入法类型，可整份复制到其他项目复用。
final class KeyboardMapView: NSView {
    let layout: KeyRootLayout

    static let keyHeight: CGFloat = 68
    static let keyGap: CGFloat = 6
    static let rowGap: CGFloat = 6
    /// 键位下方的序号带高度：位次写在键外，绝不和键名/字根抢位置。
    static let captionHeight: CGFloat = 14
    static var rowPitch: CGFloat { keyHeight + captionHeight }
    static var totalHeight: CGFloat { rowPitch * 3 + rowGap * 2 }
    /// 字根网格：3 列 × 3 行（每键最多显示 9 个，超出以省略号收尾）。
    static let rootColumns = 3
    static let rootRows = 3

    private var pressed: Character?
    /// 答案键位（含第几位）：同一个键可以出现多次，用来还原"4 位码用了哪些键、分别第几位"。
    private var answerOrder: [(letter: Character, position: Int)] = []
    private var answerKeys: Set<Character> { Set(answerOrder.map(\.letter)) }

    init(layout: KeyRootLayout = .wubi86) {
        self.layout = layout
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("\(layout.displayName) 字根键位图")
        setAccessibilityHelp("每题答案用到的键位会描边，位次以圈号标在键位下方")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var entries: [Character: KeyRootLayout.Entry] { layout.entries }
    var schemeID: String { layout.schemeID }
    var pressedLetterForTesting: String? { pressed.map(String.init) }
    var markedLettersForTesting: Set<Character> { answerKeys }
    /// 测试用：答案键位与位次（同一个键可能出现多次）。
    var markedPositionsForTesting: [(letter: Character, position: Int)] { answerOrder }

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

    /// 答完后把答案用到的键位持久描边，并在键角标出第几位；传空串清除。
    func markAnswer(_ code: String) {
        answerOrder = code.uppercased().compactMap { $0 }.enumerated()
            .map { (letter: $0.element, position: $0.offset + 1) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let gap = Self.keyGap
        let keyWidth = (bounds.width - gap * 9) / 10
        for (rowIndex, row) in layout.rows.enumerated() {
            // 每排按真实键盘错位：键数少的排整体居中，自然形成阶梯。
            let rowWidth = CGFloat(row.count) * keyWidth + CGFloat(row.count - 1) * gap
            let indent = (bounds.width - rowWidth) / 2
            let y = CGFloat(rowIndex) * (Self.rowPitch + Self.rowGap)
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
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
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
        // 左上角：编码字母（大写、加粗）；右上角：主字根；下方：其余字根（按口诀顺序）。
        drawText(String(letter), font: .monospacedSystemFont(ofSize: 13.5, weight: .bold),
                 color: isPressed ? .white : .labelColor,
                 in: NSRect(x: rect.minX + 7, y: rect.minY + 5, width: rect.width - 14, height: 17),
                 alignment: .left)
        drawText(entry?.keyName ?? "", font: .systemFont(ofSize: 16, weight: .bold), color: keyNameColor,
                 in: NSRect(x: rect.minX, y: rect.minY + 4, width: rect.width - 7, height: 19),
                 alignment: .right)
        drawRoots(entry?.roots ?? [], in: rect, color: rootColor)
        NSGraphicsContext.restoreGraphicsState()
        // 序号画在键位下方的序号带里，必须在裁切之外绘制。
        drawPositionBadge(for: letter, in: rect, tint: tint, isPressed: isPressed)
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

    /// 位次标注：写在键位**下方**的序号带里（居中），不覆盖键名与字根。
    private func drawPositionBadge(for letter: Character, in rect: NSRect, tint: NSColor, isPressed: Bool) {
        let marks = positionMarks(for: letter)
        guard !marks.isEmpty, !isPressed else { return }
        let string = NSAttributedString(string: marks, attributes: [
            .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
            .foregroundColor: tint.blended(withFraction: 0.25, of: .labelColor) ?? .labelColor])
        let size = string.size()
        string.draw(at: NSPoint(x: rect.midX - size.width / 2,
                                y: rect.maxY + (Self.captionHeight - size.height) / 2))
    }

    /// 当前答案里这个键的位次标记（①②③④），同一键多次出现会合并。
    func positionMarks(for letter: Character) -> String {
        let marks = ["①", "②", "③", "④", "⑤", "⑥", "⑦", "⑧"]
        let positions = answerOrder.filter { $0.letter == letter }.map { $0.position }
        guard !positions.isEmpty else { return "" }
        return positions.map { $0 <= marks.count ? marks[$0 - 1] : String($0) }.joined()
    }

    private func drawRoots(_ roots: [String], in rect: NSRect, color: NSColor) {
        let font = NSFont.systemFont(ofSize: 9.5)
        let shown = Self.visibleRoots(roots)
        guard !shown.isEmpty else { return }
        let columns = Self.rootColumns
        let top: CGFloat = 30
        let lineHeight = (rect.height - top - 4) / CGFloat(Self.rootRows)
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

}
