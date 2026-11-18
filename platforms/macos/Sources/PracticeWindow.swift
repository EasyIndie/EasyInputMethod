import AppKit

/// 题干字形（ADR-369）：自绘并垂直居中。
///
/// 大字号字形用 `NSTextField` 放在翻转坐标的滚动内容里会被裁掉上半部分（宋体 44pt 实测），
/// 自绘按 `boundingRect` 居中，字根「口」等方形字也能完整呈现。
final class PracticeGlyphView: NSView {
    var text: String = "" { didSet { needsDisplay = true; updateAccessibility() } }
    var font: NSFont = .systemFont(ofSize: 40, weight: .medium) {
        didSet { needsDisplay = true; updateAccessibility() }
    }

    override var isFlipped: Bool { true }

    private func updateAccessibility() {
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph,
        ]
        let box = (text as NSString).boundingRect(
            with: NSSize(width: bounds.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin], attributes: attributes)
        let rect = NSRect(x: 0, y: (bounds.height - box.height) / 2, width: bounds.width, height: box.height)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

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
        static let questionHeight: CGFloat = 48
        static let afterQuestion: CGFloat = 6
        /// 字根题的「字根」标注行（ADR-369）：字形上方一行小字，避免把 口 当成占位方框。
        static let captionHeight: CGFloat = 16
        static let afterCaption: CGFloat = 2
        /// 解锁庆祝行（ADR-369）：只在刚解锁时出现，占一行高度。
        static let unlockHeight: CGFloat = 20
        static let afterUnlock: CGFloat = 6
        static let promptHeight: CGFloat = 18
        static let afterPrompt: CGFloat = 12
        static let cardPadding: CGFloat = 14
        static let afterExplanation: CGFloat = 14
        static let codeAnswerHeight: CGFloat = 52
        static let recognitionAnswerHeight: CGFloat = 60
        static let afterAnswer: CGFloat = 12
        static let feedbackHeight: CGFloat = 22
        static let afterFeedback: CGFloat = 10
        static let navHeight: CGFloat = 28
        static let afterNav: CGFloat = 12
        static let progressHeight: CGFloat = 16
        static let progressBarHeight: CGFloat = 6
        static let afterProgressLabel: CGFloat = 5
        static let afterProgress: CGFloat = 10
        static let afterScheme: CGFloat = 12
        static let bottom: CGFloat = 16
    }

    /// 当前状态下的内容高度（题型 + 详情区 + 口诀共同决定）。
    private func contentHeight() -> CGFloat {
        var height = Gap.top + Gap.kindHeight + Gap.afterKind
        height += Gap.captionHeight + Gap.afterCaption + questionHeight + Gap.afterQuestion
        height += Gap.cardPadding + Gap.promptHeight + Gap.afterPrompt
        height += (kind.isTyping ? Gap.codeAnswerHeight : Gap.recognitionAnswerHeight) + Gap.afterAnswer
        height += PracticeExplanationView.height + Gap.afterExplanation
        height += Gap.cardPadding
        height += Gap.feedbackHeight + Gap.afterFeedback
        // 解锁庆祝行固定占位：出现/消失时不改变窗口高度，避免练习时窗口跳动（ADR-369）。
        height += Gap.unlockHeight + Gap.afterUnlock
        height += Gap.navHeight + Gap.afterNav
        height += Gap.progressHeight + Gap.afterProgressLabel + Gap.progressBarHeight + Gap.afterProgress
        if showsKeymap {
            height += Gap.afterScheme + keymapPanel.height(forWidth: Self.contentWidth - Self.margin * 2)
        }
        return height + Gap.bottom
    }

    private var window: NSWindow?
    private var content: FlippedView?
    private let glyphCaption = NSTextField(labelWithString: "")
    private let questionLabel = PracticeGlyphView()
    private let unlockLabel = NSTextField(wrappingLabelWithString: "")
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
    private let scrollView = NSScrollView()
    /// 内容区导航（ADR-362）：键盘可直达，不再需要回工具栏点「下一题」。
    private let backButton = NSButton(title: "← 上一题", target: nil, action: nil)
    private let forwardButton = NSButton(title: "下一题 →", target: nil, action: nil)
    private let revealButton = NSButton(title: "看答案", target: nil, action: nil)
    private var answered = false
    /// 答错后的重试态（ADR-366）：重打满位数即再判，空格/回车都不进位；→/按钮=放弃并下一题。
    private var retrying = false
    private let kindControl = NSSegmentedControl(labels: PracticeKind.allCases.map(\.title),
                                                 trackingMode: .selectOne, target: nil, action: nil)
    private let strokeTitle = NSTextField(labelWithString: "末笔")
    private let structureTitle = NSTextField(labelWithString: "结构")
    private let strokeButtons = Practice.strokes.map { NSButton(title: $0, target: nil, action: nil) }
    private let structureButtons = Practice.structures.map { NSButton(title: $0, target: nil, action: nil) }
    private var practiceProgress: PracticeProgress?
    private lazy var session = PracticeSession(kind: .code, progress: progress, weak: WeakChars.shared)
    private var current: PracticeQuestion? { session.question }
    private var pendingStroke: String?
    private var pendingStructure: String?
    private var lastAnswer: String?

    /// 题库规模缓存：只有一级简码题库可能小于 30，其余题库均 >30（ADR-350）。
    private var bankSizeCache: [PracticeKind: Int] = [:]
    /// 离屏测试在 `ime_config_init` 之前渲染时使用；宿主运行期为 nil。
    private var stagedUnlockOverride: Bool?

    private func bankSizeFor(_ kind: PracticeKind) -> Int {
        if let cached = bankSizeCache[kind] { return cached }
        let size: Int
        if kind == .code1 {
            size = Practice.bank(kind: .code1).count
        } else if kind == self.kind {
            size = session.bank.count
        } else {
            size = 30
        }
        let normalized = max(1, size)
        bankSizeCache[kind] = normalized
        return normalized
    }

    private func unlockedKinds() -> Set<PracticeKind> {
        var stats: [PracticeKind: Practice.KindStats] = [:]
        var sizes: [PracticeKind: Int] = [:]
        for kind in PracticeKind.allCases {
            let row = progress.stats(kind: kind)
            stats[kind] = Practice.KindStats(
                practiced: row.practiced, attempts: row.attempts, correct: row.correct)
            sizes[kind] = bankSizeFor(kind)
        }
        // 测试可显式覆盖；宿主里的显式 false 才关闭，未初始化时按默认开启。
        let staged = stagedUnlockOverride
            ?? ImeConfig.string("practice.staged_unlock").map { $0 == "true" } ?? true
        return Practice.unlockedKinds(stats: stats, bankSizes: sizes, staged: staged)
    }

    /// 禁用未解锁题型；若当前题型被锁（例如刚重置），回到第一个可用题型。
    private func applyStagedUnlock() {
        let unlocked = unlockedKinds()
        for (index, candidate) in PracticeKind.allCases.enumerated() {
            let enabled = unlocked.contains(candidate)
            kindControl.setEnabled(enabled, forSegment: index)
            kindControl.setToolTip(enabled ? nil : lockedHint(for: candidate), forSegment: index)
        }
        if !unlocked.contains(kind), let index = PracticeKind.allCases.firstIndex(where: unlocked.contains) {
            kindControl.selectedSegment = index
        }
    }

    private func lockedHint(for kind: PracticeKind) -> String {
        let kinds = PracticeKind.allCases
        guard let index = kinds.firstIndex(of: kind), index > 0 else { return "" }
        let previous = kinds[index - 1]
        let stats = progress.stats(kind: previous)
        let required = Practice.requiredPractice(bankSize: bankSizeFor(previous))
        let rate = stats.attempts > 0 ? stats.correct * 100 / stats.attempts : 0
        return "先完成「\(previous.title)」：\(required) 字、正确率 ≥90%（当前 \(stats.practiced) 字、\(rate)%）"
    }

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
        applyStagedUnlock()
        applyKindVisibility()
        reload()
        // 输入法宿主是 LSBackgroundOnly：普通窗口不一定能成为 key/前台，
        // 这里按既有设置面板的做法补一次 orderFrontRegardless（报告 262）。
        if NSApp.activationPolicy() == .prohibited { NSApp.setActivationPolicy(.accessory) }
        NSApp.activate(ignoringOtherApps: true)
        if let window { WindowPlacement.place(window) }
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
        window?.makeFirstResponder(answerView)
    }

    private func build() {
        let size = NSSize(width: Self.contentWidth, height: contentHeight())
        let window = PracticePanel(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.onKey = { [weak self] event in self?.handleNavigation(event) ?? false }
        window.title = "萤火虫 · 练习"
        window.isReleasedWhenClosed = false
        window.delegate = self
        // 内容放进滚动视图：窗口不超过屏幕可用高度，键位图+口诀展开时改为滚动。
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = buildContent()
        window.contentView = scrollView
        let toolbar = NSToolbar(identifier: "Lampyris.Practice")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        if #available(macOS 11.0, *) { window.toolbarStyle = .unified }
        self.window = window
    }

    private func buildContent() -> NSView {
        let content = FlippedView(frame: NSRect(origin: .zero,
                                                size: NSSize(width: Self.contentWidth, height: contentHeight())))
        self.content = content

        kindControl.target = self
        kindControl.action = #selector(kindChanged)
        content.addSubview(kindControl)

        glyphCaption.alignment = .center
        glyphCaption.font = .systemFont(ofSize: 11, weight: .semibold)
        glyphCaption.textColor = .secondaryLabelColor
        glyphCaption.setAccessibilityLabel("字根字形")
        content.addSubview(glyphCaption)

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
        answerView.onComplete = { [weak self] text in self?.submitCode(text) }
        answerView.onAdvance = { [weak self] in self?.nextQuestion() }
        answerView.onBack = { [weak self] in self?.previousQuestion() }
        answerView.onForward = { [weak self] in self?.nextQuestion() }
        answerView.onReveal = { [weak self] in self?.revealAnswer() }
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

        unlockLabel.alignment = .center
        unlockLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        unlockLabel.textColor = .systemGreen
        unlockLabel.isHidden = true
        content.addSubview(unlockLabel)

        for (button, action, label) in [
            (backButton, #selector(previousQuestion), "上一题（←）"),
            (revealButton, #selector(revealAnswer), "看答案（⌘↩）"),
            (forwardButton, #selector(nextQuestion), "下一题（已作答后空格或 →）"),
        ] as [(NSButton, Selector, String)] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.font = .systemFont(ofSize: 12)
            button.toolTip = label
            button.setAccessibilityLabel(label)
            content.addSubview(button)
        }
        revealButton.keyEquivalent = "\r"
        revealButton.keyEquivalentModifierMask = [.command]

        progressLabel.font = .systemFont(ofSize: 11)
        progressLabel.textColor = .secondaryLabelColor
        content.addSubview(progressLabel)

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.controlSize = .small
        progressBar.setAccessibilityLabel("练习进度")
        progressBar.setAccessibilityHelp("已练字数占题库的比例")
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

        glyphCaption.frame = NSRect(x: margin, y: y, width: inner, height: Gap.captionHeight)
        y += Gap.captionHeight + Gap.afterCaption

        questionLabel.frame = NSRect(x: margin, y: y, width: inner, height: questionHeight)
        y += questionHeight + Gap.afterQuestion

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
        // 末笔 / 结构两行在卡片内**水平居中**：标题 + 按钮作为一个整体算宽度再定起点。
        let titleWidth: CGFloat = 46
        let titleGap: CGFloat = 10
        let strokeButtonWidth: CGFloat = 66
        let strokeButtonGap: CGFloat = 8
        let strokeRowWidth = titleWidth + titleGap
            + CGFloat(strokeButtons.count) * strokeButtonWidth
            + CGFloat(max(0, strokeButtons.count - 1)) * strokeButtonGap
        var strokeX = margin + max(0, (inner - strokeRowWidth) / 2)
        strokeTitle.frame = NSRect(x: strokeX, y: y + 5, width: titleWidth, height: 18)
        strokeX += titleWidth + titleGap
        for button in strokeButtons {
            button.frame = NSRect(x: strokeX, y: y, width: strokeButtonWidth, height: 28)
            strokeX += strokeButtonWidth + strokeButtonGap
        }

        let structureY = y + 32
        let structureButtonWidth: CGFloat = 108
        let structureButtonGap: CGFloat = 8
        let structureRowWidth = titleWidth + titleGap
            + CGFloat(structureButtons.count) * structureButtonWidth
            + CGFloat(max(0, structureButtons.count - 1)) * structureButtonGap
        var structureX = margin + max(0, (inner - structureRowWidth) / 2)
        structureTitle.frame = NSRect(x: structureX, y: structureY + 5, width: titleWidth, height: 18)
        structureX += titleWidth + titleGap
        for button in structureButtons {
            button.frame = NSRect(x: structureX, y: structureY, width: structureButtonWidth, height: 28)
            structureX += structureButtonWidth + structureButtonGap
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

        unlockLabel.isHidden = unlockLabel.stringValue.isEmpty
        unlockLabel.frame = NSRect(x: margin, y: y, width: inner, height: Gap.unlockHeight)
        y += Gap.unlockHeight + Gap.afterUnlock

        // 导航行：← 上一题（左）｜ 看答案 · 下一题 →（右）。
        let navWidth: CGFloat = 96
        let revealWidth: CGFloat = 84
        backButton.frame = NSRect(x: margin, y: y, width: navWidth, height: Gap.navHeight)
        forwardButton.frame = NSRect(x: margin + inner - navWidth, y: y, width: navWidth, height: Gap.navHeight)
        revealButton.frame = NSRect(x: margin + inner - navWidth - 8 - revealWidth, y: y,
                                    width: revealWidth, height: Gap.navHeight)
        y += Gap.navHeight + Gap.afterNav

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
        // 窗口高度不超过屏幕可用区域；超出部分交给滚动，避免"顶满屏幕"。
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let limit = max(360, available - 80)
        let windowHeight = min(height, limit)
        if abs(window.contentLayoutRect.height - windowHeight) > 0.5 {
            var frame = window.frame
            let titleBar = frame.height - window.contentLayoutRect.height
            frame.origin.y += frame.height - (windowHeight + titleBar)
            frame.size.height = windowHeight + titleBar
            window.setFrame(frame, display: true, animate: false)
        }
        scrollView.frame = NSRect(origin: .zero, size: NSSize(width: Self.contentWidth, height: windowHeight))
    }

    private func showExplanation(_ question: PracticeQuestion, revealsAnswer: Bool) {
        // 本题目要求的那一项排在最前，完整码与两个简码随后——一块讲完，不再另起一行重复。
        let target: String? = {
            switch kind {
            case .roots: return "键位 \(question.code.uppercased())"
            case .phrase: return "词组码 \(question.code.uppercased())"
            case .code1: return question.short1.map { "一级 \($0.uppercased())" }
            case .code2: return question.short2.map { "二级 \($0.uppercased())" }
            case .code3: return question.short3.map { "三级 \($0.uppercased())" }
            default: return "完整码 \(question.code.uppercased())"
            }
        }()
        // 字根题的「码」只是所在键、词组题的码是词组码，都不是单字的完整码，不能当「完整码」展示（否则教错）。
        explanation.show(char: question.char, roots: question.roots,
                         recognition: question.recognition, code: kind == .roots || kind == .phrase ? "" : question.code,
                         short1: question.short1, short2: question.short2, short3: question.short3,
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
        applyStagedUnlock()
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

    /// 回上一题：回看历史，不重复计分（ADR-362）。
    @objc private func previousQuestion() {
        guard session.back() else { return }
        showCurrent()
    }

    /// 窗口级键盘导航兑底：识别码题型答完后焦点不在作答框，← / → / 空格 落到这里（ADR-371）。
    private func handleNavigation(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123:
            guard session.canGoBack else { return false }
            previousQuestion()
            return true
        case 124:
            // → 始终是下一题/跳过（答错后不想重试也用它）。
            nextQuestion()
            return true
        case 49:
            // ADR-371：空格=确认进位（输入法用空格上屏）；回车在练习里不再进位。
            guard session.currentEntry != nil, !retrying else { return false }
            nextQuestion()
            return true
        default:
            return false
        }
    }

    /// 统计：题库字数、已练字数、次数、正确率、练习进度（沿用当前题型）。
    private func updateStats() {
        let bankSize = max(1, session.bank.count)
        let stats = progress.stats(kind: kind)
        let rate = stats.attempts > 0 ? stats.correct * 100 / stats.attempts : 0
        let percent = Int((Double(stats.practiced) / Double(bankSize) * 100).rounded())
        progressLabel.stringValue = "题库 \(session.bank.count) 字 · 已练 \(stats.practiced) 字 · "
            + "\(stats.attempts) 次 · 正确率 \(rate)% · 进度 \(percent)%"
        // ADR-344/350：达标后建议下一题型；未达标时显示解锁门槛。
        if let next = Practice.nextHint(kind: kind, practiced: stats.practiced,
                                        attempts: stats.attempts, correct: stats.correct,
                                        bankSize: bankSizeFor(kind)) {
            progressLabel.stringValue += " · 可以试试「\(next)」了"
        } else {
            let kinds = PracticeKind.allCases
            if let index = kinds.firstIndex(of: kind), index + 1 < kinds.count {
                let next = kinds[index + 1]
                if !unlockedKinds().contains(next) {
                    let required = Practice.requiredPractice(bankSize: bankSizeFor(kind))
                    progressLabel.stringValue += " · 下一阶段「\(next.title)」需 \(kind.title) "
                        + "\(required) 字、正确率 ≥90%（当前 \(stats.practiced) 字、\(rate)%）"
                }
            }
        }
        progressBar.doubleValue = Double(stats.practiced) / Double(bankSize)
        progressBar.setAccessibilityValue("\(percent)%")
    }

    private func showCurrent() {
        answered = false
        retrying = false
        answerView.isAnswered = false
        answerView.clear()
        keymapPanel.map.clearFlash()
        keymapPanel.map.markAnswer("")
        pendingStroke = nil
        pendingStructure = nil
        lastAnswer = nil
        feedbackLabel.stringValue = ""
        unlockLabel.stringValue = ""
        strokeTitle.stringValue = "末笔"
        structureTitle.stringValue = "结构"
        for button in strokeButtons + structureButtons { button.state = .off }
        guard let question = current else {
            questionLabel.text = "题库为空"
            promptLabel.stringValue = kind == .roots
                ? "缺少键位字根表，无法出字根题"
                : "当前没有可出题的完整条目（需要 quality=full）"
            progressLabel.stringValue = session.summary
            glyphCaption.stringValue = ""
            glyphCaption.isHidden = true
            updateNavigation()
            relayout()
            return
        }
        answerView.setActive(true)
        answerView.capacity = capacity(for: question)
        questionLabel.text = question.char
        applyQuestionChrome()
        promptLabel.stringValue = promptText(for: question)
        if kind == .recognition {
            showExplanation(question, revealsAnswer: false)
            explanation.isHidden = false
        } else {
            explanation.showPlaceholder("答题后在这里显示字根、识别码与完整码")
            explanation.isHidden = false
        }
        updateStats()
        // 回看已有记录：直接呈现当时的答案与对错，并把格子填回去。
        if let entry = session.currentEntry { present(entry) }
        updateNavigation()
        relayout()
        if kind.isTyping, session.currentEntry == nil { window?.makeFirstResponder(answerView) }
    }

    /// 题干行高：宋体 44pt 的行距约 62pt，按系统字体 40pt 的 48pt 放会截掉字形（ADR-369）。
    private var questionHeight: CGFloat { kind == .roots ? 64 : Gap.questionHeight }

    /// 题干外观（ADR-369）：字根题的题干就是一个字形（例如「口」），40pt 渲染时和系统占位方框长得一样。
    /// 加一行「字根」标注并换用宋体，笔画粗细与衬线让它是「字」而不是「框」。
    private func applyQuestionChrome() {
        let isRoots = kind == .roots
        glyphCaption.stringValue = isRoots ? "字根" : ""
        glyphCaption.isHidden = !isRoots
        questionLabel.font = isRoots
            ? (NSFont(name: "Songti SC", size: 44) ?? .systemFont(ofSize: 40, weight: .medium))
            : .systemFont(ofSize: 40, weight: .medium)
    }

    private func capacity(for question: PracticeQuestion) -> Int {
        switch kind {
        case .roots, .code1: return 1
        case .code2: return 2
        case .code3: return 3
        case .code: return min(4, max(3, question.code.count))
        case .phrase, .recognition: return 4
        }
    }

    /// 已作答（刚答完或回看）：展示答案与对错，不写进度。
    /// `retry == true` 时（答错，ADR-366）不揭晓答案，只抖动输入框并清空，让用户重答。
    private func present(_ entry: PracticeSession.Entry, retry: Bool = false) {
        answered = !retry
        retrying = retry
        answerView.isAnswered = !retry
        answerView.setActive(!retry)
        keymapPanel.map.clearFlash()
        if kind.isTyping {
            if retry {
                answerView.clear()
            } else {
                answerView.showAnswer(entry.answer)
            }
        } else {
            if retry {
                pendingStroke = nil
                pendingStructure = nil
            } else {
                let parts = entry.answer.split(separator: "+").map(String.init)
                if parts.count == 2 {
                    pendingStroke = parts[0]
                    pendingStructure = parts[1]
                }
            }
            updateSelectionTitle()
        }
        if retry {
            explanation.showPlaceholder(kind == .recognition
                ? "答错了：重新选一个末笔和一个结构"
                : "答错了：再试一次，答对后显示字根、识别码与完整码")
            explanation.isHidden = false
            keymapPanel.map.markAnswer("")
        } else {
            showExplanation(entry.question, revealsAnswer: true)
            explanation.isHidden = false
            // 高亮的是本题要求的答案：一级/二级简码就高亮简码的键位，完整码才高亮全码。
            if let expected = kind.answer(for: entry.question) {
                keymapPanel.map.markAnswer(expected)
            }
        }
        let headline = entry.result.correct ? "✓ 正确" : (retry ? "✗ 再试一次" : "✗ 再想想")
        let typed = kind.isTyping && !entry.answer.isEmpty ? " · 你答 \(entry.answer.uppercased())" : ""
        feedbackLabel.stringValue = headline + typed
            + (entry.result.explanation.isEmpty ? "" : " · " + entry.result.explanation)
        feedbackLabel.textColor = entry.result.correct ? .systemGreen : .systemOrange
        updateStats()
        // ADR-366：达标后下一题型 tab 立即亮起（不必切题型/重开窗口）。
        applyStagedUnlock()
        updateNavigation()
        if retry {
            Shake.animate(kind.isTyping ? answerView : card)
            if kind.isTyping { window?.makeFirstResponder(answerView) }
        } else if kind == .recognition {
            // 识别码没有作答框可持焦点：交给窗口，← / → / 空格 才能继续导航。
            window?.makeFirstResponder(nil)
        }
    }

    private func updateNavigation() {
        backButton.isEnabled = session.canGoBack
        forwardButton.isEnabled = current != nil
        revealButton.isEnabled = kind.isTyping && current != nil && session.currentEntry == nil && !retrying
        forwardButton.toolTip = session.isReviewing ? "下一题（→，回到更新的题）" : "下一题（已作答后空格或 →）"
    }

    @objc private func submitCode(_ text: String) {
        guard session.currentEntry == nil else { return }
        let unlockedBefore = unlockedKinds()
        guard session.submitCode(text) != nil else { return }
        finish(unlockedBefore: unlockedBefore)
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
        guard session.currentEntry == nil else { return }
        let unlockedBefore = unlockedKinds()
        guard session.submitRecognition(stroke: stroke, structure: structure) != nil else { return }
        finish(unlockedBefore: unlockedBefore)
    }

    private func finish(unlockedBefore: Set<PracticeKind>? = nil) {
        guard let entry = session.currentEntry else { return }
        if entry.result.correct {
            present(entry)
            celebrateUnlock(before: unlockedBefore)
            announce(unlockLabel.stringValue.isEmpty
                ? feedbackLabel.stringValue
                : feedbackLabel.stringValue + "。 " + unlockLabel.stringValue)
            return
        }
        // 答错：清掉"已作答"指针进入重试态（历史与进度保留），抖动输入框并播报。
        if session.retry() {
            present(entry, retry: true)
            announce("答错了，请再试一次")
            return
        }
        present(entry)
        announce(feedbackLabel.stringValue)
    }

    /// 刚解锁了新题型时给一句正向反馈（ADR-369）：进度行只写门槛，达标瞬间没有鼓励。
    private func celebrateUnlock(before: Set<PracticeKind>?) {
        guard let before else { return }
        let newly = unlockedKinds().subtracting(before)
        guard !newly.isEmpty else { return }
        let titles = PracticeKind.allCases.filter { newly.contains($0) }.map(\.title)
        unlockLabel.stringValue = "🎉 已解锁「" + titles.joined(separator: "」「") + "」"
        unlockLabel.setAccessibilityLabel(unlockLabel.stringValue)
        relayout()
    }

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: text,
                                         .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    @objc private func revealAnswer() {
        guard let question = current, session.currentEntry == nil else { return }
        // 字根已经在上面的字根行里（字形上、键位下），这里只给完整码，避免又变成行内交替写法。
        showExplanation(question, revealsAnswer: true)
        explanation.isHidden = false
        feedbackLabel.stringValue = ""
        feedbackLabel.textColor = .secondaryLabelColor
        updateNavigation()
    }

    @objc private func resetProgress() {
        let alert = NSAlert()
        alert.messageText = "重置练习进度？"
        alert.informativeText = "会删除本机的 practice.tsv（已练字数、次数、正确率归零）和薄弱字清单 weak-chars.tsv。此操作不可撤销。"
        alert.addButton(withTitle: "重置")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        progress.reset()
        WeakChars.shared.reset()
        session.reload()
        kindControl.selectedSegment = 0
        applyStagedUnlock()
        applyKindVisibility()
        showCurrent()
    }

    @objc private func openPassage() {
        PassageWindow.shared.show()
    }

    @objc private func openProgress() {
        progress.save()
        NSWorkspace.shared.activateFileViewerSelecting([progress.url])
    }

    // MARK: 测试

    /// 离屏渲染（测试用）：建一个不显示的窗口承载视图（AppKit 控件需要 window 才能绘制）。
    func renderForTesting(kind: PracticeKind, progressURL: URL, light: Bool,
                          allUnlocked: Bool = false) -> NSBitmapImageRep? {
        // allUnlocked 只给"看非首个题型的版式/文案"用：否则未达标的题型会被锁回第一个。
        stagedUnlockOverride = !allUnlocked
        practiceProgress = PracticeProgress(url: progressURL)
        session = PracticeSession(kind: kind, progress: practiceProgress!)
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyStagedUnlock()
        applyKindVisibility()
        if let question = current {
            // 离屏渲染共用同一批控件对象：先清掉上一次渲染残留的作答内容。
            answerView.clear()
            answerView.isAnswered = false
            answerView.capacity = capacity(for: question)
            questionLabel.text = question.char
            applyQuestionChrome()
            unlockLabel.stringValue = ""
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
    /// 测试用：按当前题作答一次（走真实判分/进度/解锁刷新，ADR-366）。
    @discardableResult
    func answerForTesting(correct: Bool) -> Bool {
        guard let question = current else { return false }
        let answer = correct ? (kind.answer(for: question) ?? "") : "zzzz"
        let unlockedBefore = unlockedKinds()
        guard let result = session.submitCode(answer) else { return false }
        finish(unlockedBefore: unlockedBefore)
        return result.correct
    }

    /// 测试用：像真实键盘一样往作答框敲字母（打满位数即自动判分，ADR-370）。
    func typeForTesting(_ letters: String) {
        for character in letters {
            let text = String(character)
            guard let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)
            else { continue }
            answerView.keyDown(with: event)
        }
    }

    /// 测试用：当前题的正确作答串（小写）。
    var expectedAnswerForTesting: String {
        guard let question = current else { return "" }
        return (kind.answer(for: question) ?? "").lowercased()
    }

    /// 测试用：作答框当前内容。
    var answerTextForTesting: String { answerView.text }

    /// 测试用：字根题的字形标注与解锁庆祝文案。
    var glyphCaptionForTesting: String { glyphCaption.isHidden ? "" : glyphCaption.stringValue }
    var unlockBannerForTesting: String { unlockLabel.isHidden ? "" : unlockLabel.stringValue }

    /// 测试用：跳到下一题（等同 → / 工具栏按钮）。
    func nextForTesting() { nextQuestion() }

    /// 测试用：走窗口级键盘导航（识别码题型/无作答框时用这条路）。
    func navigateForTesting(_ keyCode: UInt16) -> Bool {
        guard let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1f}",
            charactersIgnoringModifiers: "\u{1f}", isARepeat: false, keyCode: keyCode)
        else { return false }
        return handleNavigation(event)
    }

    /// 测试用：某题型的进度统计（已练/次数/正确）。
    func statsForTesting(_ kind: PracticeKind) -> (practiced: Int, attempts: Int, correct: Int) {
        progress.stats(kind: kind)
    }

    /// 测试用：是否处于"答错重试"态（空格/回车都不会跳题）。
    var retryStateForTesting: Bool { retrying }
    /// 测试用：当前题面字/词。
    var questionForTesting: String { current?.char ?? "" }

    /// 测试用：内容区导航行（ADR-362）的标题与启用状态。
    func navigationForTesting() -> [(title: String, enabled: Bool)] {
        [backButton, revealButton, forwardButton].map { ($0.title, $0.isEnabled) }
    }

    /// 测试用：当前进度下解锁的题型与分段启用状态。
    func unlockedKindsForTesting() -> [PracticeKind] {
        let unlocked = unlockedKinds()
        return PracticeKind.allCases.filter { unlocked.contains($0) }
    }

    func kindEnabledForTesting(_ kind: PracticeKind) -> Bool {
        guard let index = PracticeKind.allCases.firstIndex(of: kind) else { return false }
        return kindControl.isEnabled(forSegment: index)
    }

    func contentViewForTesting(kind: PracticeKind, revealed: Bool = false) -> NSView? {
        stagedUnlockOverride = true
        let view = buildContent()
        kindControl.selectedSegment = PracticeKind.allCases.firstIndex(of: kind) ?? 0
        applyStagedUnlock()
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
        case .roots:
            return showsKeymap
                ? "这个字根在哪个键上？（可先对照键位图，熟了再收起）"
                : "这个字根在哪个键上？（1 位）"
        case .code1: return "打出它的一级简码（1 位）"
        case .code2: return "打出它的二级简码（2 位）"
        case .code3: return "打出它的三级简码（3 位）"
        case .code: return "打出它的完整五笔码（\(question.code.count) 位）"
        case .phrase: return "打出这个词的词组码（4 位）"
        }
    }

    /// 测试用：模拟答完后高亮答案键位。
    func markAnswerForTesting(_ code: String) {
        keymapPanel.map.markAnswer(code)
    }

    /// 测试用：展开面板里的口诀。
    func showMnemonicsForTesting(_ visible: Bool) {
        keymapPanel.showsMnemonics = visible
        relayout()
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

// MARK: - 工具栏（四个持久动作放窗口顶部；导航与看答案在内容区，ADR-362）

extension PracticeWindow: NSToolbarDelegate {
    private enum ToolbarID {
        static let reset = NSToolbarItem.Identifier("practice.reset")
        static let export = NSToolbarItem.Identifier("practice.export")
        static let keymap = NSToolbarItem.Identifier("practice.keymap")
        static let passage = NSToolbarItem.Identifier("practice.passage")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [ToolbarID.passage, .flexibleSpace, ToolbarID.keymap, ToolbarID.reset, ToolbarID.export]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: identifier)
        switch identifier {
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
        case ToolbarID.passage:
            item.label = "文章跟打"
            item.toolTip = "打开文章跟打窗口"
            item.image = NSImage(systemSymbolName: "text.book.closed", accessibilityDescription: "文章跟打")
            item.target = self
            item.action = #selector(openPassage)
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

/// 练习窗口：识别码题型答完后没有作答框持焦点，← / → / 空格 在窗口级兑底（ADR-362/371）。
private final class PracticePanel: NSWindow {
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }
}
