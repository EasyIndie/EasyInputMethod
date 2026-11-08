import AppKit

/// 练习作答输入：4 个方框（五笔码最长 4 位），自己收键、不经过输入法。
///
/// - 只接受 a–y 参与答案，`z`（万能键）只点亮键位图、不进答案；
/// - 退格删一位，`Esc` / `⌘⌫` 一次清空，回车提交；
/// - 样式参考系统验证码输入：当前格高亮描边，已填格显示大写字母。
final class PracticeAnswerView: NSView {
    static let maxLength = 4
    var onReturn: ((String) -> Void)?
    /// 每次按键回调（a–z），用于点亮键位图。
    var onLetter: ((Character) -> Void)?

    private(set) var text = "" {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override var focusRingMaskBounds: NSRect { bounds }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }
        // ⌘⌫ 一次清空
        if event.modifierFlags.contains(.command), (0x7F...0x7F).contains(characters.unicodeScalars.first?.value ?? 0) {
            clear()
            return
        }
        for scalar in characters.unicodeScalars {
            switch scalar.value {
            case 0x0D, 0x03:
                onReturn?(text)
            case 0x1B:
                clear()
            case 0x7F, 0x08:
                if !text.isEmpty { text.removeLast() }
            default:
                let value = Int(scalar.value)
                guard (65...90).contains(value) || (97...122).contains(value),
                      let scalarLetter = UnicodeScalar(value) else { continue }
                let typed = Character(String(scalarLetter).uppercased())
                onLetter?(typed)
                // z 是万能键，不是任何码的一部分：只点亮键位，不写入答案。
                guard typed != "Z", text.count < Self.maxLength else { continue }
                text.append(Character(String(scalarLetter).lowercased()))
            }
        }
    }

    func clear() { text = "" }
    func setTextForTesting(_ value: String) { text = String(value.prefix(Self.maxLength)) }

    override func draw(_ dirtyRect: NSRect) {
        let count = CGFloat(Self.maxLength)
        let gap: CGFloat = 10
        let cellWidth = min(52, (bounds.width - gap * (count - 1)) / count)
        let total = cellWidth * count + gap * (count - 1)
        var x = (bounds.width - total) / 2
        let letters = Array(text.uppercased())
        for index in 0..<Self.maxLength {
            let rect = NSRect(x: x, y: (bounds.height - 52) / 2, width: cellWidth, height: 52)
            let filled = index < letters.count
            let active = index == letters.count && letters.count < Self.maxLength
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
            NSColor.textBackgroundColor.setFill()
            path.fill()
            if active {
                NSColor.systemGreen.withAlphaComponent(0.95).setStroke()
                path.lineWidth = 2
            } else {
                NSColor.separatorColor.withAlphaComponent(filled ? 0.9 : 0.6).setStroke()
                path.lineWidth = 1
            }
            path.stroke()
            if filled {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: NSColor.labelColor]
                let string = NSAttributedString(string: String(letters[index]), attributes: attributes)
                let size = string.size()
                string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            x += cellWidth + gap
        }
    }
}
