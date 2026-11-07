import AppKit

/// 练习窗口（ADR-313）：独立、非模态、可随时关闭；不碰候选窗，不常驻焦点。
///
/// 布局用**翻转坐标**从顶部往下排，避免手动从底部算高度导致文字出界（报告 260）：
/// 题型切换 → 题干 → 提示 → 作答区 → 反馈 → 按钮 → 进度。
final class PracticeWindow: NSObject, NSWindowDelegate {
    static let shared = PracticeWindow()
    static let contentSize = NSSize(width: 460, height: 356)

    private var window: NSWindow?
    private var content: FlippedView?
    private let questionLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let answerView = PracticeAnswerView()
    private let rootRow = PracticeRootRowView()
    private var answered = false
    private let kindControl = NSSegmentedControl(labels: PracticeKind.allCases.map(\.title),
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let strokeTitle = NSTextField(labelWithString: "末笔")
    private let structureTitle = NSTextField(labelWithString: "结构")
    private let strokeButtons = Practice.strokes.map { NSButton(title: $0, target: nil, action: nil) }
    private let structureButtons = Practice.structures.map { NSButton(title: $0, target: nil, action: nil) }
    private var practiceProgress: PracticeProgress?
    private lazy var session = PracticeSession(kind: .code, progress: progress)
    private var current: PracticeQuestion? { session.question }
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
        // 输入法宿主是 LSBackgroundOnly：普通窗口不一定能成为 key/前台，
        // 这里按既有设置面板的做法补一次 orderFrontRegardless（报告 262）。
        if NSApp.activationPolicy() == .prohibited { NSApp.setActivationPolicy(.accessory) }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(answerView)
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
        promptLabel.frame = NSRect(x: margin, y: 116, width: width - margin * 2, height: 18)
        content.addSubview(promptLabel)

        // 字根行（与学习区同样式：字形上、键位下）
        rootRow.frame = NSRect(x: margin, y: 136, width: width - margin * 2, height: PracticeRootRowView.rowHeight)
        content.addSubview(rootRow)

        answerView.frame = NSRect(x: margin, y: 176, width: width - margin * 2, height: 30)
        answerView.onReturn = { [weak self] text in self?.submitCode(text) }
        content.addSubview(answerView)

        // 识别码：两行带标题的按钮组
        strokeTitle.font = .systemFont(ofSize: 11)
        strokeTitle.textColor = .secondaryLabelColor
        strokeTitle.frame = NSRect(x: margin, y: 182, width: 46, height: 18)
        content.addSubview(strokeTitle)
        for (index, button) in strokeButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStroke(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + 52 + CGFloat(index) * 72, y: 176, width: 66, height: 28)
            content.addSubview(button)
        }
        structureTitle.font = .systemFont(ofSize: 11)
        structureTitle.textColor = .secondaryLabelColor
        structureTitle.frame = NSRect(x: margin, y: 220, width: 46, height: 18)
        content.addSubview(structureTitle)
        for (index, button) in structureButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStructure(_:))
            button.tag = index
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + 52 + CGFloat(index) * 116, y: 214, width: 108, height: 28)
            content.addSubview(button)
        }

        feedbackLabel.alignment = .center
        feedbackLabel.font = .systemFont(ofSize: 12)
        feedbackLabel.frame = NSRect(x: margin, y: 250, width: width - margin * 2, height: 40)
        content.addSubview(feedbackLabel)

        let next = NSButton(title: "下一题", target: self, action: #selector(nextQuestion))
        let reveal = NSButton(title: "显示答案", target: self, action: #selector(revealAnswer))
        let export = NSButton(title: "打开进度文件", target: self, action: #selector(openProgress))
        for (index, button) in [next, reveal, export].enumerated() {
            button.bezelStyle = .rounded
            button.frame = NSRect(x: margin + CGFloat(index) * 130, y: 292, width: 120, height: 28)
            content.addSubview(button)
        }

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.frame = NSRect(x: margin, y: 326, width: width - margin * 2, height: 16)
        content.addSubview(progressLabel)
        return content
    }

    private func applyKindVisibility() {
        let isCode = kind == .code
        answerView.isHidden = !isCode
        rootRow.isHidden = !(kind == .recognition || answered)
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
        session.switchKind(kind)
        showCurrent()
    }

    @objc private func nextQuestion() {
        session.next()
        showCurrent()
    }

    private func showCurrent() {
        answered = false
        answerView.clear()
        pendingStroke = nil
        pendingStructure = nil
        lastAnswer = nil
        feedbackLabel.stringValue = ""
        strokeTitle.stringValue = "末笔"
        structureTitle.stringValue = "结构"
        guard let question = current else {
            questionLabel.stringValue = "题库为空"
            promptLabel.stringValue = "当前没有可出题的完整条目（需要 quality=full）"
            progressLabel.stringValue = session.summary
            return
        }
        questionLabel.stringValue = question.char
        promptLabel.stringValue = kind == .code
            ? "打出它的完整五笔码（\(question.code.count) 位）"
            : "按上面的字根与键位，判断末笔与结构"
        rootRow.show(question.roots)
        rootRow.isHidden = kind != .recognition
        progressLabel.stringValue = session.summary
        if kind == .code { window?.makeFirstResponder(answerView) }
    }

    @objc private func submitCode(_ text: String) {
        guard let result = session.submitCode(text) else { return }
        finish(result)
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
        guard let stroke = pendingStroke, let structure = pendingStructure else {
            feedbackLabel.stringValue = "选一个末笔和一个结构"
            feedbackLabel.textColor = .secondaryLabelColor
            return
        }
        guard let result = session.submitRecognition(stroke: stroke, structure: structure) else { return }
        finish(result)
    }

    private func finish(_ result: PracticeSession.Result) {
        answered = true
        if let question = current {
            rootRow.show(question.roots)
            rootRow.isHidden = false
        }
        feedbackLabel.stringValue = (result.correct ? "✓ 正确 · " : "✗ 再想想 · ") + result.explanation
        feedbackLabel.textColor = result.correct ? .systemGreen : .systemOrange
        progressLabel.stringValue = session.summary
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
        session = PracticeSession(kind: kind, progress: practiceProgress!)
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyKindVisibility()
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
