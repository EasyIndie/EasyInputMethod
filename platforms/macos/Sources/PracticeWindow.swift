import AppKit

/// 练习窗口（ADR-313）：独立、非模态、可随时关闭；不碰候选窗，不常驻焦点。
///
/// 布局用**翻转坐标**从顶部往下排，避免手动从底部算高度导致文字出界（报告 260）：
/// 题型切换 → 题干 → 提示 → 作答区 → 反馈 → 按钮 → 进度。
final class PracticeWindow: NSObject, NSWindowDelegate {
    static let shared = PracticeWindow()
    static let contentSize = NSSize(width: 460, height: 336)

    private var window: NSWindow?
    private var content: FlippedView?
    private let questionLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let answerField = NSTextField(string: "")
    private let kindControl = NSSegmentedControl(labels: PracticeKind.allCases.map(\.title),
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let strokeTitle = NSTextField(labelWithString: "末笔")
    private let structureTitle = NSTextField(labelWithString: "结构")
    private let strokeButtons = Practice.strokes.map { NSButton(title: $0, target: nil, action: nil) }
    private let structureButtons = Practice.structures.map { NSButton(title: $0, target: nil, action: nil) }
    private var practiceProgress: PracticeProgress?
    private var bank: [PracticeQuestion] = []
    private var current: PracticeQuestion?
    private var pendingStroke: String?
    private var pendingStructure: String?
    private var lastAnswer: String?

    private var progress: PracticeProgress {
        if let practiceProgress { return practiceProgress }
        let created = PracticeProgress(url: PracticeProgress.defaultURL())
        practiceProgress = created
        return created
    }

    private var kind: PracticeKind {
        PracticeKind.allCases[max(0, min(PracticeKind.allCases.count - 1, kindControl.selectedSegment))]
    }

    // MARK: 展示

    func show() {
        if window == nil { build() }
        kindControl.selectedSegment = 0
        applyKindVisibility()
        reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeFirstResponder(answerField)
    }

    private func build() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "萤火虫 · 练习"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = buildContent()
        window.center()
        self.window = window
    }

    private func buildContent() -> NSView {
        let content = FlippedView(frame: NSRect(origin: .zero, size: Self.contentSize))
        let width = Self.contentSize.width
        let margin: CGFloat = 24

        kindControl.frame = NSRect(x: margin, y: 20, width: width - margin * 2, height: 26)
        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        content.addSubview(kindControl)

        questionLabel.alignment = .center
        questionLabel.font = .systemFont(ofSize: 40, weight: .medium)
        questionLabel.frame = NSRect(x: margin, y: 56, width: width - margin * 2, height: 60)
        content.addSubview(questionLabel)

        promptLabel.alignment = .center
        promptLabel.font = .systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        promptLabel.frame = NSRect(x: margin, y: 120, width: width - margin * 2, height: 18)
        content.addSubview(promptLabel)

        answerField.frame = NSRect(x: margin, y: 148, width: width - margin * 2, height: 26)
        answerField.placeholderString = "输入完整五笔码后回车"
        answerField.target = self
        answerField.action = #selector(submitCode)
        answerField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        content.addSubview(answerField)

        // 识别码：两行带标题的按钮组
        strokeTitle.font = .systemFont(ofSize: 11)
        strokeTitle.textColor = .secondaryLabelColor
        strokeTitle.frame = NSRect(x: margin, y: 148, width: 32, height: 24)
        content.addSubview(strokeTitle)
        for (index, button) in strokeButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStroke(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + 36 + CGFloat(index) * 74, y: 144, width: 68, height: 28)
            content.addSubview(button)
        }
        structureTitle.font = .systemFont(ofSize: 11)
        structureTitle.textColor = .secondaryLabelColor
        structureTitle.frame = NSRect(x: margin, y: 186, width: 32, height: 24)
        content.addSubview(structureTitle)
        for (index, button) in structureButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStructure(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + 36 + CGFloat(index) * 108, y: 182, width: 100, height: 28)
            content.addSubview(button)
        }

        feedbackLabel.alignment = .center
        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.frame = NSRect(x: margin, y: 218, width: width - margin * 2, height: 40)
        content.addSubview(feedbackLabel)

        let next = NSButton(title: "下一题", target: self, action: #selector(nextQuestion))
        let reveal = NSButton(title: "显示答案", target: self, action: #selector(revealAnswer))
        let export = NSButton(title: "打开进度文件", target: self, action: #selector(openProgress))
        for (index, button) in [next, reveal, export].enumerated() {
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + CGFloat(index) * 130, y: 264, width: 120, height: 28)
            content.addSubview(button)
        }

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.frame = NSRect(x: margin, y: 300, width: width - margin * 2, height: 16)
        content.addSubview(progressLabel)
        return content
    }

    private func applyKindVisibility() {
        let isCode = kind == .code
        answerField.isHidden = !isCode
        strokeTitle.isHidden = isCode
        structureTitle.isHidden = isCode
        for button in strokeButtons + structureButtons { button.isHidden = isCode }
    }

    // MARK: 交互

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
            promptLabel.stringValue = "当前没有可出题的完整条目（需要 quality=full）"
            return
        }
        current = bank.randomElement()
        lastAnswer = nil
        answerField.stringValue = ""
        pendingStroke = nil
        pendingStructure = nil
        feedbackLabel.stringValue = ""
        guard let question = current else { return }
        questionLabel.stringValue = question.char
        promptLabel.stringValue = kind == .code
            ? "打出它的完整五笔码（\(question.code.count) 位）"
            : "拆解：\(question.rootHint)"
        progressLabel.stringValue = progress.summary
        if kind == .code { window?.makeFirstResponder(answerField) }
    }

    @objc private func submitCode() {
        guard let question = current else { return }
        let answer = answerField.stringValue
        let correct = Practice.judgeCode(answer, question: question)
        lastAnswer = answer
        finish(correct: correct, explanation: "完整码 \(question.code.uppercased()) · 字根 \(question.rootHint)")
    }

    @objc private func pickStroke(_ sender: NSButton) {
        pendingStroke = Practice.strokes[sender.tag]
        updateSelectionTitle()
        evaluateRecognition()
    }

    @objc private func pickStructure(_ sender: NSButton) {
        pendingStructure = Practice.structures[sender.tag]
        updateSelectionTitle()
        evaluateRecognition()
    }

    private func updateSelectionTitle() {
        if let stroke = pendingStroke { strokeTitle.stringValue = "末笔 \(stroke)" }
        if let structure = pendingStructure { structureTitle.stringValue = "结构 \(structure)" }
    }

    private func evaluateRecognition() {
        guard let question = current, let stroke = pendingStroke, let structure = pendingStructure else {
            feedbackLabel.stringValue = "选一个末笔和一个结构"
            feedbackLabel.textColor = .secondaryLabelColor
            return
        }
        let correct = Practice.judgeRecognition(stroke: stroke, structure: structure, question: question)
        let letter = question.recognition?.letter ?? "—"
        finish(correct: correct, explanation: "识别码 \(letter)（\(stroke)·\(structure)）")
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

    // MARK: 测试

    /// 离屏渲染（测试用）：建一个不显示的窗口承载视图（AppKit 控件需要 window 才能绘制）。
    func renderForTesting(kind: PracticeKind, progressURL: URL, light: Bool) -> NSBitmapImageRep? {
        practiceProgress = PracticeProgress(url: progressURL)
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyKindVisibility()
        bank = Practice.bank(kind: kind)
        current = bank.first
        if let question = current {
            questionLabel.stringValue = question.char
            promptLabel.stringValue = kind == .code
                ? "打出它的完整五笔码(\(question.code.count) 位)"
                : "拆解：\(question.rootHint)"
            feedbackLabel.stringValue = kind == .code ? "✓ 正确 · 完整码 \(question.code.uppercased())"
                                                      : "选一个末笔和一个结构"
        }
        progressLabel.stringValue = progress.summary
        let host = NSWindow(contentRect: NSRect(origin: .zero, size: Self.contentSize),
                            styleMask: [.titled], backing: .buffered, defer: false)
        host.contentView = view
        if let appearance = NSAppearance(named: light ? .aqua : .darkAqua) { host.appearance = appearance }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 版式自检（测试用）：所有控件必须落在内容区里，且不与顶部题型控件重叠。
    func layoutProblemsForTesting(kind: PracticeKind) -> [String] {
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyKindVisibility()
        var problems: [String] = []
        let bounds = view.bounds
        for sub in view.subviews where !sub.isHidden {
            if !bounds.contains(sub.frame) {
                problems.append("\(type(of: sub)) 越界 \(sub.frame)")
            }
            if sub !== kindControl, sub.frame.intersects(kindControl.frame.insetBy(dx: 0, dy: -4)) {
                problems.append("\(type(of: sub)) 与题型控件重叠")
            }
        }
        return problems
    }
}

/// 顶部起算的容器：文字与控件按"距顶部"排，避免出界。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
