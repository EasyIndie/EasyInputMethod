import AppKit

/// 五笔 25 键字根分布图（QWERTY 物理排布）。
///
/// 每个键画出该键的键名字根与字母，按区着色（横/竖/撇/捺/折）。
/// 用户敲键时对应键位点亮，答完后把答案用到的键位持久描边，方便建立"键位 ↔ 字根"的肌肉记忆。
final class WubiKeyboardMapView: NSView {
    /// 键位数据来自方案（`KeyRootLayout`），换方案只换 layout。
    let layout: KeyRootLayout

    init(layout: KeyRootLayout = .wubi86) {
        self.layout = layout
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// 供测试与无障碍使用的只读视图。
    var entries: [Character: KeyRootLayout.Entry] { layout.entries }
    var schemeID: String { layout.schemeID }

    static let keyHeight: CGFloat = 32
    static let rowGap: CGFloat = 4
    static var totalHeight: CGFloat { keyHeight * 3 + rowGap * 2 }

    private var pressed: Character?
    private var answerKeys: Set<Character> = []

    override var isFlipped: Bool { true }

    /// 敲键时的瞬时点亮；`nil` 熄灭。
    func flash(_ letter: Character) {
        pressed = letter.uppercased().first
        needsDisplay = true
    }

    func clearFlash() {
        pressed = nil
        needsDisplay = true
    }

    /// 答完后把答案用到的键位持久描边；传空集合清除。
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
        let key = layout.entries[letter]
        let isPressed = pressed == letter
        let isAnswer = answerKeys.contains(letter)
        let path = NSBezierPath(roundedRect: rect, xRadius: 4.5, yRadius: 4.5)

        let tint = Self.zoneColor(key?.zone ?? 0)
        (isPressed ? tint.withAlphaComponent(0.85) : tint.withAlphaComponent(0.13)).setFill()
        path.fill()
        if isAnswer && !isPressed {
            tint.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 1.4
            path.stroke()
        }

        let letterColor: NSColor = isPressed ? .white : .secondaryLabelColor
        let rootColor: NSColor = isPressed ? .white : (isAnswer ? (tint.blended(withFraction: 0.25, of: .labelColor) ?? tint) : .labelColor)
        draw(letter: letter, root: key?.keyName ?? "", rect: rect, rootColor: rootColor, letterColor: letterColor)
    }

    private func draw(letter: Character, root: String, rect: NSRect,
                      rootColor: NSColor, letterColor: NSColor) {
        let rootText = NSAttributedString(string: root, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: rootColor,
            .paragraphStyle: centered()])
        rootText.draw(in: NSRect(x: rect.minX, y: rect.minY + 2, width: rect.width, height: 19))
        let letterText = NSAttributedString(string: String(letter), attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: letterColor,
            .paragraphStyle: centered()])
        letterText.draw(in: NSRect(x: rect.minX, y: rect.minY + 19, width: rect.width, height: 12))
    }

    private func centered() -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return paragraph
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

    override func accessibilityChildren() -> [Any]? { nil }

    var pressedLetterForTesting: String? { pressed.map(String.init) }
    var markedLettersForTesting: Set<Character> { answerKeys }

    func accessibilitySummary() -> String {
        "\(layout.displayName) 字根键位图：" + layout.entries.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.keyName)" }.joined(separator: "，")
    }
}
