import AppKit

/// 练习作答输入框：自己收键，不经过输入法（避免回车被 IME 吃掉、字母被组合）。
/// 只接受 a–y 小写字母、退格与回车；其余按键忽略。
final class PracticeAnswerView: NSView {
    var onReturn: ((String) -> Void)?
    private(set) var text = "" {
        didSet { needsDisplay = true }
    }
    var placeholder = "输入完整五笔码后回车"

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else { return }
        for scalar in characters.unicodeScalars {
            switch scalar.value {
            case 0x0D, 0x03:
                onReturn?(text)
            case 0x7F, 0x08:
                if !text.isEmpty { text.removeLast() }
            default:
                let value = Int(scalar.value)
                if (65...89).contains(value) || (97...121).contains(value),
                   let letter = UnicodeScalar(value) {
                    text.append(Character(String(letter).lowercased()))
                }
            }
        }
    }


    func clear() { text = "" }
    func setTextForTesting(_ value: String) { text = value }

    override func draw(_ dirtyRect: NSRect) {
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        NSColor.textBackgroundColor.setFill()
        border.fill()
        NSColor.systemGreen.setStroke()
        border.lineWidth = 2
        border.stroke()
        let shown = text.isEmpty ? placeholder : text.uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: text.isEmpty ? NSFont.systemFont(ofSize: 13)
                                : NSFont.monospacedSystemFont(ofSize: 15, weight: .medium),
            .foregroundColor: text.isEmpty ? NSColor.placeholderTextColor : NSColor.labelColor,
        ]
        NSAttributedString(string: shown, attributes: attributes)
            .draw(in: bounds.insetBy(dx: 8, dy: 5))
    }
}
