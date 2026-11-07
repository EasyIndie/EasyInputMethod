import AppKit

/// 练习里的字根行：与学习区同一套样式——上面字形、下面大写键位，一目了然。
final class PracticeRootRowView: NSView {
    static let cellWidth: CGFloat = 46
    static let rowHeight: CGFloat = 36
    private(set) var roots: [(glyph: String, key: String)] = []
    override var isFlipped: Bool { true }

    func show(_ roots: [(glyph: String, key: String)]) {
        self.roots = Array(roots.prefix(6))
        setAccessibilityLabel(self.roots.map { "\($0.glyph)，键 \($0.key)" }.joined(separator: "；"))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        var x: CGFloat = 0
        for root in roots {
            let glyphRect = NSRect(x: x, y: 0, width: Self.cellWidth, height: 21)
            let keyRect = NSRect(x: x, y: 21, width: Self.cellWidth, height: 15)
            let glyph = NSMutableAttributedString(string: root.glyph, attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: NSColor.labelColor])
            var paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            glyph.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: glyph.length))
            glyph.draw(in: glyphRect)
            let key = NSMutableAttributedString(string: root.key.uppercased(), attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor])
            paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            key.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: key.length))
            key.draw(in: keyRect)
            x += Self.cellWidth
        }
    }
}
