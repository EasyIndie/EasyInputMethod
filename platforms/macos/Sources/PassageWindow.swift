import AppKit

/// 文章跟打窗口（ADR-347）：显示一条自编短句，用户在输入框里照着打，回车逐字比对。
///
/// 独立、非模态；不新增全局热键，从练习窗口工具栏进入。只统计本次会话，不落盘、不上报。
final class PassageWindow: NSObject, NSWindowDelegate {
    static let shared = PassageWindow()
    private static let width: CGFloat = 720
    private static let height: CGFloat = 260
    private static let margin: CGFloat = 24

    private var window: NSWindow?
    private let targetLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let input = NSTextField()
    private let resultLabel = NSTextField(wrappingLabelWithString: "")
    private var target = PassageBank.sentences.first ?? ""
    private var rounds = 0
    private var exact = 0

    func show() {
        if window == nil { build() }
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(input)
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.height),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "文章跟打"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        let content = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        window.contentView = content

        targetLabel.font = .systemFont(ofSize: 20, weight: .regular)
        targetLabel.textColor = .labelColor
        targetLabel.setAccessibilityLabel("目标短句")
        content.addSubview(targetLabel)

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.setAccessibilityLabel("跟打进度")
        content.addSubview(progressLabel)

        input.font = .systemFont(ofSize: 16)
        input.placeholderString = "照着上面的短句输入，回车判定"
        input.setAccessibilityLabel("跟打输入")
        input.setAccessibilityHelp("按当前输入法输入上面的短句，回车判定；下一句会清空输入")
        input.target = self
        input.action = #selector(submit)
        content.addSubview(input)

        resultLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        resultLabel.setAccessibilityLabel("跟打结果")
        content.addSubview(resultLabel)

        let next = NSButton(title: "下一句", target: self, action: #selector(nextSentence))
        next.bezelStyle = .rounded
        next.setAccessibilityLabel("下一句")
        content.addSubview(next)

        let retry = NSButton(title: "重来", target: self, action: #selector(retry))
        retry.bezelStyle = .rounded
        retry.setAccessibilityLabel("重来")
        content.addSubview(retry)

        var y = Self.height - Self.margin - 44
        targetLabel.frame = NSRect(x: Self.margin, y: y, width: Self.width - Self.margin * 2, height: 44)
        y -= 24
        progressLabel.frame = NSRect(x: Self.margin, y: y, width: Self.width - Self.margin * 2, height: 16)
        y -= 48
        input.frame = NSRect(x: Self.margin, y: y, width: Self.width - Self.margin * 2, height: 28)
        y -= 36
        resultLabel.frame = NSRect(x: Self.margin, y: y, width: Self.width - Self.margin * 2, height: 36)
        y -= 44
        next.frame = NSRect(x: Self.margin, y: y, width: 96, height: 28)
        retry.frame = NSRect(x: Self.margin + 108, y: y, width: 96, height: 28)

        self.window = window
        showCurrent()
    }

    private func showCurrent() {
        targetLabel.stringValue = target
        targetLabel.setAccessibilityValue(target)
        progressLabel.stringValue = rounds == 0
            ? "第 1 句 · 共 \(PassageBank.sentences.count) 句"
            : "第 \(rounds) 句 · 本机正确 \(exact) 句（\(exact * 100 / max(rounds, 1))%）"
        input.stringValue = ""
        resultLabel.stringValue = ""
        resultLabel.textColor = .labelColor
    }

    @objc private func submit() {
        let typed = input.stringValue
        guard !typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        rounds += 1
        let result = PassageBank.judge(target: target, typed: typed)
        if result.isExact {
            exact += 1
            resultLabel.stringValue = "正确 · \(result.total)/\(result.total)"
            resultLabel.textColor = NSColor.systemGreen
            resultLabel.setAccessibilityValue("正确")
        } else {
            let position = (result.firstMismatch ?? 0) + 1
            var detail = "第 \(position) 个字不对"
            if let expected = result.expected { detail += "：应为「\(expected)」" }
            if let typed = result.typed { detail += "，输入「\(typed)」" }
            resultLabel.stringValue = "\(detail) · 正确 \(result.correct)/\(result.total)"
            resultLabel.textColor = NSColor.systemOrange
            resultLabel.setAccessibilityValue(resultLabel.stringValue)
        }
        progressLabel.stringValue = "第 \(rounds) 句 · 本机正确 \(exact) 句（\(exact * 100 / max(rounds, 1))%）"
    }

    @objc private func nextSentence() {
        target = PassageBank.next(after: target)
        showCurrent()
        window?.makeFirstResponder(input)
    }

    @objc private func retry() {
        input.stringValue = ""
        resultLabel.stringValue = ""
        resultLabel.textColor = .labelColor
        window?.makeFirstResponder(input)
    }
}
