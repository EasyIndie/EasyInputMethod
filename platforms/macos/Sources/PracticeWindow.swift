import AppKit

/// 练习窗口（ADR-313）：独立、非模态、可随时关闭；不碰候选窗，不常驻焦点。
final class PracticeWindow: NSObject, NSWindowDelegate {
    static let shared = PracticeWindow()

    private var window: NSWindow?
    private let questionLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(labelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let answerField = NSTextField(string: "")
    private let kindControl = NSSegmentedControl(labels: PracticeKind.allCases.map(\.title),
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let strokeButtons = Practice.strokes.map { NSButton(title: $0, target: nil, action: nil) }
    private let structureButtons = Practice.structures.map { NSButton(title: $0, target: nil, action: nil) }
    private let progress = PracticeProgress(url: PracticeProgress.defaultURL())
    private var bank: [PracticeQuestion] = []
    private var current: PracticeQuestion?
    private var pendingStroke: String?
    private var pendingStructure: String?

    private var kind: PracticeKind {
        PracticeKind.allCases[max(0, min(PracticeKind.allCases.count - 1, kindControl.selectedSegment))]
    }

    func show() {
        if window == nil { build() }
        kindControl.selectedSegment = 0
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(answerField)
    }

    private func build() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "萤火虫 · 练习"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let container = NSView()
        var y: CGFloat = 250
        func place(_ view: NSView, height: CGFloat, width: CGFloat = 360) {
            view.frame = NSRect(x: 30, y: y, width: width, height: height)
            container.addSubview(view)
            y -= height + 10
        }

        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        place(kindControl, height: 26)

        questionLabel.font = .systemFont(ofSize: 34, weight: .medium)
        place(questionLabel, height: 44)

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        place(detailLabel, height: 18)

        answerField.placeholderString = "输入完整五笔码后回车"
        answerField.target = self
        answerField.action = #selector(submitCode)
        place(answerField, height: 24)

        for (index, button) in strokeButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStroke(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 30 + CGFloat(index) * 70, y: y, width: 64, height: 26)
            container.addSubview(button)
        }
        y -= 36
        for (index, button) in structureButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStructure(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: 30 + CGFloat(index) * 100, y: y, width: 94, height: 26)
            container.addSubview(button)
        }
        y -= 40

        feedbackLabel.font = .systemFont(ofSize: 12)
        place(feedbackLabel, height: 18)

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        place(progressLabel, height: 16)

        let next = NSButton(title: "下一题", target: self, action: #selector(nextQuestion))
        next.bezelStyle = .rounded
        next.frame = NSRect(x: 30, y: 12, width: 90, height: 26)
        container.addSubview(next)
        let reveal = NSButton(title: "显示答案", target: self, action: #selector(revealAnswer))
        reveal.bezelStyle = .rounded
        reveal.frame = NSRect(x: 130, y: 12, width: 90, height: 26)
        container.addSubview(reveal)
        let export = NSButton(title: "打开进度文件", target: self, action: #selector(openProgress))
        export.bezelStyle = .rounded
        export.frame = NSRect(x: 230, y: 12, width: 110, height: 26)
        container.addSubview(export)

        window.contentView = container
        self.window = window
        applyKindVisibility()
    }

    private func applyKindVisibility() {
        let isCode = kind == .code
        answerField.isHidden = !isCode
        for button in strokeButtons + structureButtons { button.isHidden = isCode }
    }

    @objc private func kindChanged() {
        applyKindVisibility()
        reload()
    }

    private func reload() {
        bank = Practice.bank(kind: kind)
        current = nil
        nextQuestion()
    }

    @objc private func nextQuestion() {
        guard !bank.isEmpty else {
            questionLabel.stringValue = "题库为空"
            detailLabel.stringValue = "当前没有可出题的完整条目（需要 quality=full）"
            return
        }
        current = bank.randomElement()
        answerField.stringValue = ""
        pendingStroke = nil
        pendingStructure = nil
        feedbackLabel.stringValue = ""
        guard let question = current else { return }
        questionLabel.stringValue = question.char
        if kind == .code {
            detailLabel.stringValue = "打出它的完整五笔码（\(question.code.count) 位）"
        } else {
            detailLabel.stringValue = "拆解：\(question.rootHint) · 选末笔与结构"
        }
        progressLabel.stringValue = progress.summary
        if kind == .code { window?.makeFirstResponder(answerField) }
    }

    @objc private func submitCode() {
        guard let question = current else { return }
        let correct = Practice.judgeCode(answerField.stringValue, question: question)
        finish(correct: correct, explanation: "完整码 \(question.code.uppercased()) · 字根 \(question.rootHint)")
    }

    @objc private func pickStroke(_ sender: NSButton) {
        pendingStroke = Practice.strokes[sender.tag]
        evaluateRecognition()
    }

    @objc private func pickStructure(_ sender: NSButton) {
        pendingStructure = Practice.structures[sender.tag]
        evaluateRecognition()
    }

    private func evaluateRecognition() {
        guard let question = current, let stroke = pendingStroke, let structure = pendingStructure else {
            feedbackLabel.stringValue = "选末笔与结构各一个"
            return
        }
        let correct = Practice.judgeRecognition(stroke: stroke, structure: structure, question: question)
        let letter = question.recognition?.letter ?? "—"
        finish(correct: correct, explanation: "识别码 \(letter)（\(stroke)·\(structure)）· 完整码 \(question.code.uppercased())")
    }

    private func finish(correct: Bool, explanation: String) {
        guard let question = current else { return }
        progress.record(char: question.char, kind: kind, correct: correct)
        feedbackLabel.stringValue = (correct ? "✓ 正确 · " : "✗ 再想想 · ") + explanation
        feedbackLabel.textColor = correct ? .systemGreen : .systemOrange
        progressLabel.stringValue = progress.summary
    }

    @objc private func revealAnswer() {
        guard let question = current else { return }
        feedbackLabel.stringValue = "答案：\(question.code.uppercased()) · 字根 \(question.rootHint)"
        feedbackLabel.textColor = .secondaryLabelColor
    }

    @objc private func openProgress() {
        progress.save()
        NSWorkspace.shared.activateFileViewerSelecting([progress.url])
    }
}
