import AppKit

/// 练习窗口（ADR-313）：独立、非模态、可随时关闭；不碰候选窗，不常驻焦点。
///
/// 布局用**翻转坐标**从顶部往下排，避免手动从底部算高度导致文字出界（报告 260）：
/// 题型切换 → 题干 → 提示 → 作答区 → 反馈 → 按钮 → 进度。
final class PracticeWindow: NSObject, NSWindowDelegate {
    static let shared = PracticeWindow()
    static let contentWidth: CGFloat = 720
    static let margin: CGFloat = 24
    /// 行距常量：所有纵向间距集中在这里，高度由内容算出来（自适应）。
    private enum Gap {
        static let top: CGFloat = 16
        static let kindHeight: CGFloat = 26
        static let afterKind: CGFloat = 14
        static let questionHeight: CGFloat = 60
        static let afterQuestion: CGFloat = 4
        static let promptHeight: CGFloat = 18
        static let afterPrompt: CGFloat = 12
        static let afterExplanation: CGFloat = 14
        static let codeAnswerHeight: CGFloat = 30
        static let recognitionAnswerHeight: CGFloat = 92
        static let afterAnswer: CGFloat = 12
        static let feedbackHeight: CGFloat = 30
        static let afterFeedback: CGFloat = 10
        static let actionsHeight: CGFloat = 28
        static let afterActions: CGFloat = 10
        static let progressHeight: CGFloat = 16
        static let progressBarHeight: CGFloat = 6
        static let afterProgressLabel: CGFloat = 5
        static let afterProgress: CGFloat = 8
        static let schemeHeight: CGFloat = 18
        static let afterScheme: CGFloat = 8
        static let afterMnemonic: CGFloat = 8
        static let bottom: CGFloat = 16
    }

    /// 口诀文本（区名一列 + 说明一列，制表位对齐）。
    private func mnemonicText(width: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 52)]
        style.headIndent = 52
        style.lineSpacing = 4
        return NSAttributedString(
            string: keyboardMap.layout.mnemonicsByZone
                .map { "\($0.name)\t\($0.text)" }.joined(separator: "\n"),
            attributes: [.font: NSFont.systemFont(ofSize: 10.5),
                         .foregroundColor: NSColor.secondaryLabelColor,
                         .paragraphStyle: style])
    }

    private func mnemonicHeight(width: CGFloat) -> CGFloat {
        let bounds = mnemonicText(width: width).boundingRect(
            with: NSSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return ceil(bounds.height) + 6
    }

    /// 当前状态下的内容高度（题型 + 详情区 + 口诀共同决定）。
    private func contentHeight() -> CGFloat {
        var height = Gap.top + Gap.kindHeight + Gap.afterKind
        height += Gap.questionHeight + Gap.afterQuestion + Gap.promptHeight + Gap.afterPrompt
        height += (kind.isTyping ? Gap.codeAnswerHeight : Gap.recognitionAnswerHeight) + Gap.afterAnswer
        height += PracticeExplanationView.height + Gap.afterExplanation
        height += Gap.feedbackHeight + Gap.afterFeedback
        height += Gap.actionsHeight + Gap.afterActions
        height += Gap.progressHeight + Gap.afterProgressLabel + Gap.progressBarHeight + Gap.afterProgress
        if detailsToggle.state == .on {
            height += Gap.schemeHeight + Gap.afterScheme
            height += KeyboardMapView.totalHeight
            if mnemonicToggle.state == .on {
                height += Gap.afterMnemonic + mnemonicHeight(width: Self.contentWidth - Self.margin * 2)
            }
        }
        return height + Gap.bottom
    }

    private var window: NSWindow?
    private var content: FlippedView?
    private let questionLabel = NSTextField(labelWithString: "")
    private let promptLabel = NSTextField(labelWithString: "")
    private let feedbackLabel = NSTextField(wrappingLabelWithString: "")
    private let progressLabel = NSTextField(labelWithString: "")
    private let answerView = PracticeAnswerView()
    private let explanation = PracticeExplanationView()
    private let keyboardMap = KeyboardMapView(layout: KeyRootLayout.load())
    private let schemeLabel = NSTextField(labelWithString: "")
    private let detailsToggle = NSButton(checkboxWithTitle: "键位图", target: nil, action: nil)
    private let mnemonicToggle = NSButton(checkboxWithTitle: "口诀", target: nil, action: nil)
    private let mnemonicLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private var actionButtons: [NSButton] = []
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
        let size = NSSize(width: Self.contentWidth, height: contentHeight())
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "萤火虫 · 练习"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = buildContent()
        window.center()
        self.window = window
    }

    private func buildContent() -> NSView {
        let content = FlippedView(frame: NSRect(origin: .zero,
                                                size: NSSize(width: Self.contentWidth, height: contentHeight())))
        self.content = content

        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        content.addSubview(kindControl)

        questionLabel.alignment = .center
        questionLabel.font = .systemFont(ofSize: 40, weight: .medium)
        content.addSubview(questionLabel)

        promptLabel.alignment = .center
        promptLabel.font = .systemFont(ofSize: 12)
        promptLabel.textColor = .secondaryLabelColor
        content.addSubview(promptLabel)

        // 拆解整体：字根格 + 识别码 + 完整码/简码
        explanation.frame = NSRect(x: 0, y: 0, width: 0, height: PracticeExplanationView.height)
        content.addSubview(explanation)

        answerView.onLetter = { [weak self] letter in self?.keyboardMap.flash(letter) }
        answerView.onReturn = { [weak self] text in self?.submitCode(text) }
        content.addSubview(answerView)

        strokeTitle.font = .systemFont(ofSize: 11)
        strokeTitle.textColor = .secondaryLabelColor
        content.addSubview(strokeTitle)
        for (index, button) in strokeButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStroke(_:))
            button.tag = index
            button.bezelStyle = .rounded
            content.addSubview(button)
        }
        structureTitle.font = .systemFont(ofSize: 11)
        structureTitle.textColor = .secondaryLabelColor
        content.addSubview(structureTitle)
        for (index, button) in structureButtons.enumerated() {
            button.target = self
            button.action = #selector(pickStructure(_:))
            button.tag = index
            button.bezelStyle = .rounded
            content.addSubview(button)
        }

        feedbackLabel.alignment = .center
        feedbackLabel.font = .systemFont(ofSize: 12)
        content.addSubview(feedbackLabel)

        let next = iconButton("arrow.right.circle", tooltip: "下一题",
                              action: #selector(nextQuestion))
        let reveal = iconButton("eye", tooltip: "显示答案", action: #selector(revealAnswer))
        let reset = iconButton("arrow.counterclockwise", tooltip: "重置练习进度",
                               action: #selector(resetProgress))
        let export = iconButton("doc.text", tooltip: "打开进度文件", action: #selector(openProgress))
        actionButtons = [next, reveal, reset, export]

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        content.addSubview(progressLabel)

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small
        content.addSubview(progressBar)

        schemeLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        schemeLabel.textColor = .secondaryLabelColor
        schemeLabel.stringValue = "\(keyboardMap.layout.displayName) · 25 键字根分布"
        schemeLabel.setAccessibilityLabel("当前编码方案：\(keyboardMap.layout.displayName)")
        content.addSubview(schemeLabel)

        // 详情区（键位图 + 口诀）整体可显隐：默认关闭，练习页以精简模式呈现。
        detailsToggle.target = self
        detailsToggle.action = #selector(toggleDetails)
        detailsToggle.state = .off
        detailsToggle.font = .systemFont(ofSize: 11)
        detailsToggle.controlSize = .small
        content.addSubview(detailsToggle)

        mnemonicToggle.target = self
        mnemonicToggle.action = #selector(toggleMnemonics)
        mnemonicToggle.state = .off
        mnemonicToggle.font = .systemFont(ofSize: 11)
        mnemonicToggle.controlSize = .small
        content.addSubview(mnemonicToggle)

        mnemonicLabel.isHidden = true
        mnemonicLabel.maximumNumberOfLines = 0
        mnemonicLabel.cell?.wraps = true
        mnemonicLabel.font = .systemFont(ofSize: 10.5)
        mnemonicLabel.textColor = .secondaryLabelColor
        mnemonicLabel.attributedStringValue = mnemonicText(width: Self.contentWidth - Self.margin * 2)
        mnemonicLabel.setAccessibilityLabel("五笔助记口诀")
        content.addSubview(mnemonicLabel)

        content.addSubview(keyboardMap)
        relayout()
        return content
    }

    /// 纵向排布：从顶部按当前题型与口诀开关逐段落下，窗口高度随之自适应。
    private func relayout() {
        guard content != nil else { return }
        let width = Self.contentWidth
        let margin = Self.margin
        let inner = width - margin * 2
        var y = Gap.top

        kindControl.frame = NSRect(x: margin, y: y, width: inner, height: Gap.kindHeight)
        y += Gap.kindHeight + Gap.afterKind

        questionLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.questionHeight)
        y += Gap.questionHeight + Gap.afterQuestion

        promptLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.promptHeight)
        y += Gap.promptHeight + Gap.afterPrompt

        // 作答区（输入框 / 末笔·结构）在题面下方，答案区在其下。
        answerView.frame = NSRect(x: margin, y: y, width: inner, height: Gap.codeAnswerHeight)
        strokeTitle.frame = NSRect(x: margin, y: y + 5, width: 46, height: 18)
        for (index, button) in strokeButtons.enumerated() {
            button.frame = NSRect(x: margin + 52 + CGFloat(index) * 72, y: y, width: 66, height: 28)
        }
        let structureY = y + 32
        structureTitle.frame = NSRect(x: margin, y: structureY + 5, width: 46, height: 18)
        for (index, button) in structureButtons.enumerated() {
            button.frame = NSRect(x: margin + 52 + CGFloat(index) * 116, y: structureY, width: 108, height: 28)
        }
        y += (kind.isTyping ? Gap.codeAnswerHeight : Gap.recognitionAnswerHeight) + Gap.afterAnswer

        explanation.frame = NSRect(x: margin, y: y, width: inner, height: PracticeExplanationView.height)
        y += PracticeExplanationView.height + Gap.afterExplanation

        feedbackLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.feedbackHeight)
        y += Gap.feedbackHeight + Gap.afterFeedback

        let buttons = actionButtons
        let buttonSize: CGFloat = 34
        let buttonGap: CGFloat = 14
        let totalWidth = CGFloat(buttons.count) * buttonSize + CGFloat(max(0, buttons.count - 1)) * buttonGap
        var buttonX = (width - totalWidth) / 2
        for button in buttons {
            button.frame = NSRect(x: buttonX, y: y - 3, width: buttonSize, height: buttonSize)
            buttonX += buttonSize + buttonGap
        }
        y += Gap.actionsHeight + Gap.afterActions

        // 进度行右侧常驻"键位图与口诀"开关；打开后才在下方展开详情区。
        let detailsShown = detailsToggle.state == .on
        progressLabel.frame = NSRect(x: margin, y: y + 2, width: inner - 200, height: Gap.progressHeight)
        progressBar.frame = NSRect(x: margin, y: y + Gap.progressHeight + Gap.afterProgressLabel,
                                   width: inner - 200, height: Gap.progressBarHeight)
        detailsToggle.frame = NSRect(x: width - margin - 96, y: y - 1, width: 96, height: 18)
        mnemonicToggle.frame = NSRect(x: width - margin - 96 - 64, y: y - 1, width: 60, height: 18)
        y += Gap.progressHeight + Gap.afterProgressLabel + Gap.progressBarHeight + Gap.afterProgress

        schemeLabel.isHidden = !detailsShown
        mnemonicToggle.isHidden = !detailsShown
        keyboardMap.isHidden = !detailsShown
        mnemonicLabel.isHidden = !(detailsShown && mnemonicToggle.state == .on)
        if detailsShown {
            schemeLabel.frame = NSRect(x: margin, y: y + 2, width: inner, height: Gap.schemeHeight - 2)
            y += Gap.schemeHeight + Gap.afterScheme

            keyboardMap.frame = NSRect(x: margin, y: y, width: inner, height: KeyboardMapView.totalHeight)
            y += KeyboardMapView.totalHeight

            if mnemonicToggle.state == .on {
                y += Gap.afterMnemonic
                mnemonicLabel.frame = NSRect(x: margin, y: y, width: inner,
                                             height: mnemonicHeight(width: inner))
            }
        }
        resizeWindowToFit()
    }

    private func resizeWindowToFit() {
        let height = contentHeight()
        content?.frame = NSRect(origin: .zero, size: NSSize(width: Self.contentWidth, height: height))
        guard let window else { return }
        var frame = window.frame
        let delta = frame.height - (height + (frame.height - window.contentLayoutRect.height))
        if abs(delta) > 0.5 {
            frame.origin.y += frame.height - (height + (frame.height - window.contentLayoutRect.height))
            frame.size.height = height + (frame.height - window.contentLayoutRect.height)
            window.setFrame(frame, display: true, animate: false)
        }
    }

    /// 图标按钮：悬浮提示代替文字标题。
    private func iconButton(_ symbol: String, tooltip: String, action: Selector) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
                                ?? NSImage(), target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        content?.addSubview(button)
        return button
    }

    private func showExplanation(_ question: PracticeQuestion, revealsAnswer: Bool) {
        // 本题目要求的那一项排在最前，完整码与两个简码随后——一块讲完，不再另起一行重复。
        let target: String? = {
            switch kind {
            case .code1: return question.short1.map { "一级 \($0.uppercased())" }
            case .code2: return question.short2.map { "二级 \($0.uppercased())" }
            default: return "完整码 \(question.code.uppercased())"
            }
        }()
        explanation.show(char: question.char, roots: question.roots,
                         recognition: question.recognition, code: question.code,
                         short1: question.short1, short2: question.short2,
                         target: target, revealsAnswer: revealsAnswer)
    }

    private func applyKindVisibility() {
        let isTyping = kind.isTyping
        answerView.isHidden = !isTyping
        explanation.isHidden = !(kind == .recognition || answered)
        strokeTitle.isHidden = isTyping
        structureTitle.isHidden = isTyping
        for button in strokeButtons + structureButtons { button.isHidden = isTyping }
    }

    // MARK: 交互

    @objc private func kindChanged() {
        applyKindVisibility()
        relayout()
        reload()
    }

    private func reload() {
        session.switchKind(kind)
        showCurrent()
    }

    @objc private func toggleMnemonics() {
        relayout()
    }

    @objc private func toggleDetails() {
        relayout()
    }

    @objc private func nextQuestion() {
        session.next()
        showCurrent()
    }

    /// 统计：题库字数、已练字数、次数、正确率、练习进度（沿用当前题型）。
    private func updateStats() {
        let bankSize = max(1, session.bank.count)
        let stats = progress.stats(kind: kind)
        let rate = stats.attempts > 0 ? stats.correct * 100 / stats.attempts : 0
        let percent = Int((Double(stats.practiced) / Double(bankSize) * 100).rounded())
        progressLabel.stringValue = "题库 \(session.bank.count) 字 · 已练 \(stats.practiced) 字 · "
            + "\(stats.attempts) 次 · 正确率 \(rate)% · 进度 \(percent)%"
        progressBar.doubleValue = Double(stats.practiced) / Double(bankSize)
    }

    private func showCurrent() {
        answered = false
        answerView.clear()
        keyboardMap.clearFlash()
        keyboardMap.markAnswer("")
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
        promptLabel.stringValue = kind.prompt(for: question)
        if kind == .recognition {
            showExplanation(question, revealsAnswer: false)
            explanation.isHidden = false
        } else {
            explanation.showPlaceholder("答题后在这里显示字根、识别码与完整码")
            explanation.isHidden = false
        }
        updateStats()
        if kind.isTyping { window?.makeFirstResponder(answerView) }
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
        keyboardMap.clearFlash()
        if let question = current {
            showExplanation(question, revealsAnswer: true)
            explanation.isHidden = false
        }
        if let question = current { keyboardMap.markAnswer(question.code) }
        feedbackLabel.stringValue = (result.correct ? "✓ 正确" : "✗ 再想想")
            + (result.explanation.isEmpty ? "" : " · " + result.explanation)
        feedbackLabel.textColor = result.correct ? .systemGreen : .systemOrange
        updateStats()
    }

    @objc private func revealAnswer() {
        guard let question = current else { return }
        // 字根已经在上面的字根行里（字形上、键位下），这里只给完整码，避免又变成行内交替写法。
        showExplanation(question, revealsAnswer: true)
        explanation.isHidden = false
        feedbackLabel.stringValue = ""
        feedbackLabel.textColor = .secondaryLabelColor
    }

    @objc private func resetProgress() {
        let alert = NSAlert()
        alert.messageText = "重置练习进度？"
        alert.informativeText = "会删除本机的 practice.tsv（已练字数、次数、正确率归零）。此操作不可撤销。"
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        progress.reset()
        session.reload()
        showCurrent()
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
            promptLabel.stringValue = kind.prompt(for: question)
            feedbackLabel.stringValue = kind.isTyping
                ? "✓ 正确 · \(kind.title) \(kind.answer(for: question)?.uppercased() ?? "")"
                : "选一个末笔和一个结构"
        }
        progressLabel.stringValue = progress.summary
        let host = NSWindow(contentRect: view.frame,
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
