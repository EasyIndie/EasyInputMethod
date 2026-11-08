import AppKit

/// 练习的"拆解 + 识别码 + 完整码/简码"整体展示（与学习区同一套视觉语言）。
///
/// 上排：字根格（字形上、大写键位下）；右侧：识别码两行（说明 + 大写字母）；
/// 下排：完整码，有简码时一并给出。未揭晓答案时只画字根格，不泄题。
final class PracticeExplanationView: NSView {
    static let cellWidth: CGFloat = 46
    static let height: CGFloat = 58

    private var roots: [(glyph: String, key: String)] = []
    private var recognition: (letter: String, stroke: String, structure: String)?
    private var code: String?
    private var short1: String?
    private var short2: String?
    private var revealsAnswer = true
    override var isFlipped: Bool { true }

    func show(char: String, roots: [(glyph: String, key: String)],
              recognition: (letter: String, stroke: String, structure: String)?,
              code: String, short1: String?, short2: String?, revealsAnswer: Bool) {
        self.roots = Array(roots.prefix(6))
        self.recognition = recognition
        self.code = code
        self.short1 = short1
        self.short2 = short2
        self.revealsAnswer = revealsAnswer
        setAccessibilityLabel(accessibilityText(char: char))
        needsDisplay = true
    }

    private func accessibilityText(char: String) -> String {
        var parts = roots.map { "\($0.glyph)，键 \($0.key)" }
        if revealsAnswer, let recognition {
            parts.append("识别码 \(recognition.letter)，\(recognition.stroke)·\(recognition.structure)")
        }
        if revealsAnswer, let code { parts.append("完整码 \(code.uppercased())") }
        return parts.joined(separator: "；")
    }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for root in roots {
            drawCentered(root.glyph, font: .systemFont(ofSize: 15), color: .labelColor,
                         rect: NSRect(x: x, y: 0, width: Self.cellWidth, height: 21))
            drawCentered(root.key.uppercased(), font: .monospacedSystemFont(ofSize: 10.5, weight: .regular),
                         color: .secondaryLabelColor,
                         rect: NSRect(x: x, y: 21, width: Self.cellWidth, height: 15))
            x += Self.cellWidth
        }

        var recognitionWidth: CGFloat = 0
        if revealsAnswer, let recognition {
            let blockX = x + 12
            let line1 = "识别码：\(recognition.stroke)·\(recognition.structure)结构"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor.secondaryLabelColor]
            NSAttributedString(string: line1, attributes: attributes)
                .draw(at: NSPoint(x: blockX, y: 1))
            drawCentered(recognition.letter, font: .monospacedSystemFont(ofSize: 11.5, weight: .medium),
                         color: .secondaryLabelColor,
                         rect: NSRect(x: blockX, y: 18, width: 40, height: 16), alignLeft: true)
            recognitionWidth = 150
        }

        if revealsAnswer, let code {
            var summary = "完整码 " + code.uppercased()
            if let short = short1 ?? short2 { summary += "   简码 " + short.uppercased() }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor]
            NSAttributedString(string: summary, attributes: attributes)
                .draw(at: NSPoint(x: 0, y: 40))
        }
        _ = recognitionWidth
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, rect: NSRect,
                              alignLeft: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignLeft ? .left : .center
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph]).draw(in: rect)
    }
}
