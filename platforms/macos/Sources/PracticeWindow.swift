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
        static let afterQuestion: CGFloat = 8
        static let promptHeight: CGFloat = 18
        static let afterPrompt: CGFloat = 14
        static let cardPadding: CGFloat = 20
        static let afterExplanation: CGFloat = 14
        static let codeAnswerHeight: CGFloat = 52
        static let recognitionAnswerHeight: CGFloat = 64
        static let afterAnswer: CGFloat = 14
        static let feedbackHeight: CGFloat = 24
        static let afterFeedback: CGFloat = 12
        static let progressHeight: CGFloat = 16
        static let progressBarHeight: CGFloat = 6
        static let afterProgressLabel: CGFloat = 5
        static let afterProgress: CGFloat = 12
        static let afterScheme: CGFloat = 12
        static let bottom: CGFloat = 16
    }

    /// 当前状态下的内容高度（题型 + 详情区 + 口诀共同决定）。
    private func contentHeight() -> CGFloat {
        var height = Gap.top + Gap.kindHeight + Gap.afterKind
        height += Gap.questionHeight + Gap.afterQuestion
        height += Gap.cardPadding + Gap.promptHeight + Gap.afterPrompt
        height += (kind.isTyping ? Gap.codeAnswerHeight : Gap.recognitionAnswerHeight) + Gap.afterAnswer
        height += PracticeExplanationView.height + Gap.afterExplanation
        height += Gap.cardPadding
        height += Gap.feedbackHeight + Gap.afterFeedback
        height += Gap.progressHeight + Gap.afterProgressLabel + Gap.progressBarHeight + Gap.afterProgress
        if showsKeymap {
            height += Gap.afterScheme + keymapPanel.height(forWidth: Self.contentWidth - Self.margin * 2)
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
    private let keymapPanel = KeymapPanelView(layout: KeyRootLayout.load())
    /// 键位图面板是否显示（由顶部工具栏的「键位图」按钮切换）。
    private var showsKeymap = false
    private let progressBar = NSProgressIndicator()
    private let card = NSBox()
    private var toolbarButtons: [NSButton] = []
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
        let toolbar = NSToolbar(identifier: "Lampyris.Practice")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
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

        card.boxType = .custom
        card.titlePosition = .noTitle
        card.cornerRadius = 16
        // 动态语义色：亮色用极浅黑、暗色用极浅白，两种外观都能看出"分组但不抢戏"。
        card.fillColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.045)
        }
        card.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.10)
                : NSColor.black.withAlphaComponent(0.08)
        }
        card.borderWidth = 1
        content.addSubview(card, positioned: .below, relativeTo: nil)

        answerView.onLetter = { [weak self] letter in self?.keymapPanel.map.flash(letter) }
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
            button.setButtonType(.pushOnPushOff)
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
            button.setButtonType(.pushOnPushOff)
            content.addSubview(button)
        }

        feedbackLabel.alignment = .center
        feedbackLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        content.addSubview(feedbackLabel)

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        content.addSubview(progressLabel)

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small
        content.addSubview(progressBar)

        // 键位图面板（含方案名与口诀开关）自包含；是否显示由顶部工具栏决定。
        keymapPanel.onHeightChange = { [weak self] in self?.relayout() }
        keymapPanel.isHidden = !showsKeymap
        content.addSubview(keymapPanel)
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

        // 卡片：提示语 → 作答 → 讲解 → 开关，全都在同一张分组卡片里（识别码题型同构）。
        let cardTop = y
        promptLabel.frame = NSRect(x: margin + Gap.cardPadding, y: cardTop + Gap.cardPadding,
                                   width: inner - Gap.cardPadding * 2, height: Gap.promptHeight)
        y = cardTop + Gap.cardPadding + Gap.promptHeight + Gap.afterPrompt
        // 识别码题：字根是判断依据，必须排在"末笔 / 结构"选择之前；打码题则先作答再看讲解。
        if kind == .recognition {
            explanation.frame = NSRect(x: margin, y: y, width: inner, height: PracticeExplanationView.height)
            y += PracticeExplanationView.height + Gap.afterExplanation
        }

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

        if kind != .recognition {
            explanation.frame = NSRect(x: margin, y: y, width: inner, height: PracticeExplanationView.height)
            y += PracticeExplanationView.height + Gap.afterExplanation
        }

        let cardHeight = y + Gap.cardPadding - cardTop
        card.frame = NSRect(x: margin - 2, y: cardTop, width: inner + 4, height: cardHeight)
        y = cardTop + cardHeight + Gap.afterExplanation

        feedbackLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.feedbackHeight)
        y += Gap.feedbackHeight + Gap.afterFeedback

        progressLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.progressHeight)
        progressBar.frame = NSRect(x: margin, y: y + Gap.progressHeight + Gap.afterProgressLabel,
                                   width: inner, height: Gap.progressBarHeight)
        y += Gap.progressHeight + Gap.afterProgressLabel + Gap.progressBarHeight + Gap.afterProgress

        keymapPanel.isHidden = !showsKeymap
        if showsKeymap {
            let panelHeight = keymapPanel.height(forWidth: inner)
            keymapPanel.frame = NSRect(x: margin, y: y, width: inner, height: panelHeight)
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
    private func iconButton(_ symbol: String, tooltip: String, action: Selector,
                            prominent: Bool = false) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        if prominent {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            button.layer?.cornerRadius = 9
            button.contentTintColor = .white
            button.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)) ?? image
        } else {
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            button.layer?.cornerRadius = 9
            button.contentTintColor = .labelColor
            button.image = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) ?? image
        }
        button.imagePosition = .imageOnly
        button.toolTip = tooltip
        button.setAccessibilityLabel(tooltip)
        button.refusesFirstResponder = true
        content?.addSubview(button)
        return button
    }

    private func answerHeight() -> CGFloat {
        kind.isTyping ? Gap.codeAnswerHeight : Gap.recognitionAnswerHeight
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



    @objc private func toggleKeymap(_ sender: Any?) {
        showsKeymap.toggle()
        (sender as? NSButton)?.state = showsKeymap ? .on : .off
        // 提示语可能引用"上面的字根与键位"，需要跟着显隐改口。
        if let question = current { promptLabel.stringValue = promptText(for: question) }
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
        keymapPanel.map.clearFlash()
        keymapPanel.map.markAnswer("")
        pendingStroke = nil
        pendingStructure = nil
        lastAnswer = nil
        feedbackLabel.stringValue = ""
        strokeTitle.stringValue = "末笔"
        structureTitle.stringValue = "结构"
        for button in strokeButtons + structureButtons { button.state = .off }
        guard let question = current else {
            questionLabel.stringValue = "题库为空"
            promptLabel.stringValue = "当前没有可出题的完整条目（需要 quality=full）"
            progressLabel.stringValue = session.summary
            return
        }
        answerView.setActive(true)
        answerView.capacity = {
            switch kind {
            case .code1: return 1
            case .code2: return 2
            case .code: return min(4, max(3, question.code.count))
            case .recognition: return 4
            }
        }()
        questionLabel.stringValue = question.char
        promptLabel.stringValue = promptText(for: question)
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

    /// 选中态用按钮自身的高亮表示；左侧标题保持"末笔"/"结构"，避免被值挤到显示不全。
    private func updateSelectionTitle() {
        for (index, button) in strokeButtons.enumerated() {
            button.state = Practice.strokes[index] == pendingStroke ? .on : .off
        }
        for (index, button) in structureButtons.enumerated() {
            button.state = Practice.structures[index] == pendingStructure ? .on : .off
        }
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
        keymapPanel.map.clearFlash()
        answerView.setActive(false)
        if let question = current {
            showExplanation(question, revealsAnswer: true)
            explanation.isHidden = false
        }
        // 高亮的是本题要求的答案：一级/二级简码就高亮简码的键位，完整码才高亮全码。
        if let question = current, let expected = kind.answer(for: question) {
            keymapPanel.map.markAnswer(expected)
        }
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
            promptLabel.stringValue = promptText(for: question)
            feedbackLabel.stringValue = kind.isTyping
                ? "✓ 正确 · \(kind.title) \(kind.answer(for: question)?.uppercased() ?? "")"
                : "选一个末笔和一个结构"
        }
        progressLabel.stringValue = progress.summary
        let host = NSWindow(contentRect: view.frame,
                            styleMask: [.titled], backing: .buffered, defer: false)
        if let appearance = NSAppearance(named: light ? .aqua : .darkAqua) { host.appearance = appearance }
        host.backgroundColor = .windowBackgroundColor
        host.contentView = view
        view.appearance = host.effectiveAppearance
        host.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    /// 测试用：返回构建好的内容视图（用于离屏或真实窗口截图）。
    func contentViewForTesting(kind: PracticeKind, revealed: Bool = false) -> NSView? {
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyKindVisibility()
        showCurrent()
        updateStats()
        if revealed, let question = current {
            showExplanation(question, revealsAnswer: true)
            explanation.isHidden = false
            feedbackLabel.stringValue = "✓ 正确"
            feedbackLabel.textColor = .systemGreen
        }
        return view
    }

    /// 提示语随「键位图是否展开」自适应，避免让用户去看一块没显示的区域。
    private func promptText(for question: PracticeQuestion) -> String {
        switch kind {
        case .recognition:
            return showsKeymap
                ? "按上面的字根与键位，判断末笔与结构"
                : "看拆解出的字根，判断末笔与结构"
        case .code1: return "打出它的一级简码（1 位）"
        case .code2: return "打出它的二级简码（2 位）"
        case .code: return "打出它的完整五笔码（\(question.code.count) 位）"
        }
    }

    /// 测试用：模拟答完后高亮答案键位。
    func markAnswerForTesting(_ code: String) {
        keymapPanel.map.markAnswer(code)
    }

    /// 测试用：显示/隐藏键位图面板（等同工具栏「键位图」）。
    func setKeymapVisibleForTesting(_ visible: Bool) {
        showsKeymap = visible
        relayout()
    }

    /// 测试用：把工具栏挂到给定窗口（复现真实外观）。
    func attachToolbarForTesting(to window: NSWindow) {
        let toolbar = NSToolbar(identifier: "Lampyris.Practice.Testing")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
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
                problems.append("\(type(of: sub)) 与题型控件重叠 \(sub.frame)")
            }
        }
        return problems
    }
}

// MARK: - 工具栏（五个动作统一放窗口顶部）

extension PracticeWindow: NSToolbarDelegate {
    private enum ToolbarID {
        static let next = NSToolbarItem.Identifier("practice.next")
        static let reveal = NSToolbarItem.Identifier("practice.reveal")
        static let reset = NSToolbarItem.Identifier("practice.reset")
        static let export = NSToolbarItem.Identifier("practice.export")
        static let keymap = NSToolbarItem.Identifier("practice.keymap")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.next, ToolbarID.reveal, .flexibleSpace, ToolbarID.keymap,
         ToolbarID.reset, ToolbarID.export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
        case ToolbarID.next:
            item.label = "下一题"
            item.toolTip = "下一题（回车）"
            item.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: "下一题")
            item.target = self
            item.action = #selector(nextQuestion)
        case ToolbarID.reveal:
            item.label = "显示答案"
            item.toolTip = "显示答案"
            item.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "显示答案")
            item.target = self
            item.action = #selector(revealAnswer)
        case ToolbarID.reset:
            item.label = "重置进度"
            item.toolTip = "重置练习进度"
            item.image = NSImage(systemSymbolName: "arrow.counterclockwise",
                                 accessibilityDescription: "重置练习进度")
            item.target = self
            item.action = #selector(resetProgress)
        case ToolbarID.export:
            item.label = "进度文件"
            item.toolTip = "打开进度文件"
            item.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: "打开进度文件")
            item.target = self
            item.action = #selector(openProgress)
        case ToolbarID.keymap:
            item.label = "键位图"
            item.toolTip = "显示或隐藏键位字根图"
            item.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "键位图")
            item.target = self
            item.action = #selector(toggleKeymap(_:))
        default:
            return nil
        }
        return item
    }
}

/// 顶部起算的容器：文字与控件按"距顶部"排，避免出界。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
