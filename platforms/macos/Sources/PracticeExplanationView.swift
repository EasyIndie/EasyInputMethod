import AppKit

/// 练习的「拆解 + 识别码 + 码/简码」整体展示（与学习区同一套视觉语言）。
///
/// 上排：字根格（字形上、大写键位下）；右侧：识别码两行（说明 + 大写字母）；
/// 下排：本题目要求的那一项排最前，随后是完整码与一/二级简码。未揭晓答案时只画字根格，不泄题。
final class PracticeExplanationView: NSView {
    static let cellWidth: CGFloat = 46
    static let height: CGFloat = 54

    private var roots: [(glyph: String, key: String)] = []
    private var recognition: (letter: String, stroke: String, structure: String)?
    private var code: String?
    private var short1: String?
    private var short2: String?
    private var target: String?
    private var placeholder: String?
    private var revealsAnswer = true

    override var isFlipped: Bool { true }

    func showPlaceholder(_ text: String) {
        roots = []
        recognition = nil
        code = nil
        short1 = nil
        short2 = nil
        target = nil
        revealsAnswer = false
        placeholder = text
        setAccessibilityLabel(text)
        needsDisplay = true
    }

    func show(char: String, roots: [(glyph: String, key: String)],
              recognition: (letter: String, stroke: String, structure: String)?,
              code: String, short1: String?, short2: String?, target: String? = nil,
              revealsAnswer: Bool) {
        self.roots = Array(roots.prefix(6))
        self.recognition = recognition
        self.code = code
        self.short1 = short1
        self.short2 = short2
        self.target = target
        self.revealsAnswer = revealsAnswer
        self.placeholder = nil
        setAccessibilityLabel(accessibilityText(char: char))
        needsDisplay = true
    }

    /// 下排文字：本题目答案 → 完整码 → 一级 → 二级（去重）。
    private var summaryParts: [String] {
        var parts: [String] = []
        if let target, !target.isEmpty { parts.append(target) }
        if let code {
            let full = "完整码 " + code.uppercased()
            if !parts.contains(full) { parts.append(full) }
        }
        if let short1 {
            let text = "一级 " + short1.uppercased()
            if !parts.contains(text) { parts.append(text) }
        }
        if let short2 {
            let text = "二级 " + short2.uppercased()
            if !parts.contains(text) { parts.append(text) }
        }
        return parts
    }

    private func accessibilityText(char: String) -> String {
        var parts = roots.map { "\($0.glyph)，键 \($0.key)" }
        if revealsAnswer, let recognition {
            parts.append("识别码 \(recognition.letter)，\(recognition.stroke)·\(recognition.structure)")
        }
        if revealsAnswer { parts.append(contentsOf: summaryParts) }
        return parts.joined(separator: "；")
    }

    override func draw(_ dirtyRect: NSRect) {
        if let placeholder {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let text = NSAttributedString(string: placeholder, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.tertiaryLabelColor,
                .paragraphStyle: style])
            let size = text.size()
            text.draw(at: NSPoint(x: max(0, (bounds.width - size.width) / 2),
                                  y: max(0, (bounds.height - size.height) / 2)))
            return
        }

        // 整块内容水平居中：先算总宽（字根格 + 识别码块），再从中线起画。
        let rootsWidth = CGFloat(roots.count) * Self.cellWidth
        let hasRecognition = revealsAnswer && recognition != nil
        let recognitionWidth: CGFloat = hasRecognition ? 170 : 0
        let totalWidth = rootsWidth + recognitionWidth
        var x = max(0, (bounds.width - totalWidth) / 2)
        for root in roots {
            drawCentered(root.glyph, font: .systemFont(ofSize: 15), color: .labelColor,
                         rect: NSRect(x: x, y: 0, width: Self.cellWidth, height: 21))
            drawCentered(root.key.uppercased(), font: .monospacedSystemFont(ofSize: 10.5, weight: .regular),
                         color: .secondaryLabelColor,
                         rect: NSRect(x: x, y: 21, width: Self.cellWidth, height: 15))
            x += Self.cellWidth
        }

        if revealsAnswer, let recognition {
            let blockX = x + 14
            let line1 = "识别码：\(recognition.stroke)·\(recognition.structure)结构"
            NSAttributedString(string: line1, attributes: [
                .font: NSFont.systemFont(ofSize: 10.5),
                .foregroundColor: NSColor.secondaryLabelColor])
                .draw(at: NSPoint(x: blockX, y: 1))
            drawCentered(recognition.letter, font: .monospacedSystemFont(ofSize: 11.5, weight: .medium),
                         color: .secondaryLabelColor,
                         rect: NSRect(x: blockX, y: 18, width: 40, height: 16), alignLeft: true)
        }

        if revealsAnswer {
            let summary = summaryParts.joined(separator: "   ")
            guard !summary.isEmpty else { return }
            let string = NSAttributedString(string: summary, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor])
            let width = string.size().width
            string.draw(at: NSPoint(x: max(0, (bounds.width - width) / 2), y: 38))
        }
    }

    private func drawCentered(_ text: String, font: NSFont, color: NSColor, rect: NSRect,
                              alignLeft: Bool = false) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignLeft ? .left : .center
        NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph]).draw(in: rect)
    }
}
