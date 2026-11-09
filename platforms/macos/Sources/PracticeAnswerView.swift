import AppKit

/// 练习作答输入：4 个方框（五笔码最长 4 位），自己收键、不经过输入法。
///
/// - 只接受 a–y 参与答案，`z`（万能键）只点亮键位图、不进答案；
/// - 退格删一位，`Esc` / `⌘⌫` 一次清空，回车提交；
/// - 样式参考系统验证码输入：当前格高亮描边，已填格显示大写字母。
final class PracticeAnswerView: NSView {
    static let maxLength = 4
    /// 本次题目的位数（一级 1 / 二级 2 / 完整码 3–4），决定画几个方格。
    var capacity = 4 {
        didSet {
            capacity = max(1, min(Self.maxLength, capacity))
            if text.count > capacity { text = String(text.prefix(capacity)) }
            needsDisplay = true
        }
    }
    var onReturn: ((String) -> Void)?
    /// 每次按键回调（a–z），用于点亮键位图。
    var onLetter: ((Character) -> Void)?

    private(set) var text = "" {
        didSet { needsDisplay = true }
    }
    /// 提交后收起焦点描边，避免"答完了还停在格子上"的错觉。
    private(set) var isActive = true

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("编码输入")
        setAccessibilityHelp("输入字母，回车提交；Esc 或 ⌘⌫ 清空")
    }

    override func accessibilityValue() -> Any? {
        text.isEmpty ? "空（\(capacity) 位）" : text.uppercased()
    }
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
                guard typed != "Z", text.count < capacity else { continue }
                text.append(Character(String(scalarLetter).lowercased()))
            }
        }
    }

    func clear() { text = "" }

    func setActive(_ active: Bool) {
        isActive = active
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let count = CGFloat(capacity)
        let gap: CGFloat = 10
        let cellWidth = min(46, (bounds.width - gap * (count - 1)) / count)
        let total = cellWidth * count + gap * (count - 1)
        var x = (bounds.width - total) / 2
        let letters = Array(text.uppercased())
        for index in 0..<capacity {
            let rect = NSRect(x: x, y: (bounds.height - 46) / 2, width: cellWidth, height: 46)
            let filled = index < letters.count
            let active = isActive && index == letters.count && letters.count < capacity
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
            (active ? NSColor.controlBackgroundColor : NSColor.quaternaryLabelColor.withAlphaComponent(0.10)).setFill()
            path.fill()
            if active {
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 2
            } else {
                NSColor.separatorColor.withAlphaComponent(filled ? 0.9 : 0.6).setStroke()
                path.lineWidth = 1
            }
            path.stroke()
            if filled {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .semibold),
                    .foregroundColor: NSColor.labelColor]
                let string = NSAttributedString(string: String(letters[index]), attributes: attributes)
                let size = string.size()
                string.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            }
            x += cellWidth + gap
        }
    }
}
