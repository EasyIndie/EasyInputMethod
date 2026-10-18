import Cocoa
import ime

// Local preview adapter; engine state and candidates come from the production FFI.
final class PreviewInput: NSTextView {
    let session: ImeSession
    let candidates = CandidateWindow()
    private var committed = ""
    private let previewStorage = NSTextStorage()
    private var lastFeedback: (String, Bool, Bool, Bool, Bool)?
    var status: ((String) -> Void)?
    var stateChanged: (() -> Void)?
    var persistModeChanges = false

    init(session: ImeSession) {
        self.session = session
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        previewStorage.addLayoutManager(layout)
        layout.addTextContainer(container)
        super.init(frame: NSRect(x: 0, y: 0, width: 700, height: 220), textContainer: container)
        font = .systemFont(ofSize: 24)
        isRichText = false
        textContainerInset = NSSize(width: 16, height: 16)
        setAccessibilityLabel("调试输入区")
        // 鼠标点选候选（T-MVP-06）。
        candidates.onSelect = { [weak self] index in
            guard let self, let text = self.session.select(index) else { return }
            self.committed += text
            self.refresh()
        }
    }
    required init?(coder: NSCoder) { return nil }

    // Receive raw keys here instead of invoking the installed system input method.
    override var inputContext: NSTextInputContext? { nil }

    override func keyDown(with event: NSEvent) {
        session.markKeyWhileShift()
        let shortcut = session.shortcut(event, persistMode: persistModeChanges)
        if shortcut.consumed {
            refresh()
            if shortcut == .failed { status?(ImeConfig.errorMessage() ?? "设置未保存，请重试。") }
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            super.keyDown(with: event)
            return
        }
        guard let text = event.charactersIgnoringModifiers, let scalar = text.unicodeScalars.first else { return }
        if let count = ImeConfig.int("candidate.count") { session.setPageSize(count) }
        if session.isComposing, scalar.value == 0xF72C || scalar.value == 0xF72D {
            session.page(scalar.value == 0xF72C ? -1 : 1)
        } else if session.isComposing, ImeConfig.bool("candidate.page_with_comma"),
            scalar == "," || scalar == "."
        {
            session.page(scalar == "," ? -1 : 1)
        } else if scalar == "\r" || scalar == "\n" {
            if session.isComposing {
                if case .committed(let raw) = session.feed(scalar.value) { committed += raw }
            } else { committed += "\n" }
        } else {
            let input = !session.isEnglish && scalar.isASCII && scalar.properties.isAlphabetic
                ? String(scalar).lowercased().unicodeScalars.first?.value : scalar.value
            guard let input else { return }
            if flags.contains(.shift), scalar.properties.isAlphabetic, !session.isComposing {
                committed += text
            } else {
                switch session.feed(input) {
                case .committed(let value): committed += value
                case .consumed: break
                case .passThrough:
                    if scalar.value == 127 || scalar.value == 8 {
                        if !committed.isEmpty { committed.removeLast() }
                    } else if scalar.value >= 32 { committed += text }
                case .failure(let code): status?("引擎错误：\(code)")
                }
            }
        }
        refresh()
    }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let other = flags.contains(.control) || flags.contains(.option) || flags.contains(.command)
        session.noteModifierChange(event)
        if session.shiftTransition(isDown: flags.contains(.shift), otherModifier: other) {
            refresh()
        }
    }

    func refresh() {
        stateChanged?()
        let content = NSMutableAttributedString(string: committed, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        content.append(NSAttributedString(string: session.buffer, attributes: [
            .font: NSFont.systemFont(ofSize: 24), .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.controlAccentColor,
        ]))
        textStorage?.setAttributedString(content)
        setSelectedRange(NSRange(location: content.length, length: 0))
        let values = session.candidates(limit: ImeConfig.int("candidate.count") ?? 9)
        let summary = values.map { "\(CandidateTextPresentation.display($0.text))[\($0.source.label)]" }.joined(separator: " · ")
        status?("\(session.variantErrorMessage.map { $0 + "   " } ?? "")词库：\(session.dictionaryError == IME_OK ? "正常" : "读写失败")   页：\(session.pageIndex + 1)/\(session.pageCount)   组合：\(session.buffer.isEmpty ? "（空）" : session.buffer)   候选：\(summary)")
        let status = CandidateStatus(
            mode: session.mode, english: session.isEnglish, fullWidth: session.isFullWidth,
            traditional: session.isTraditional,
            chinesePunctuation: (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese")
        let caret = firstRect(forCharacterRange: NSRange(location: content.length, length: 0), actualRange: nil)
        let feedback = (status.mode, status.english, status.fullWidth, status.traditional,
                        status.chinesePunctuation)
        if let last = lastFeedback, last != feedback {
            if session.isComposing {
                candidates.updateStatus(status)
            } else {
                let message: String
                if last.0 != feedback.0 {
                    message = StateFeedback.mode(status.mode)
                } else if last.1 != feedback.1 {
                    message = StateFeedback.language(status.english)
                } else if last.2 != feedback.2 {
                    message = StateFeedback.width(status.fullWidth)
                } else if last.3 != feedback.3 {
                    message = StateFeedback.variant(status.traditional)
                } else {
                    message = StateFeedback.punctuation(status.chinesePunctuation)
                }
                StateHUDController.shared.show(message)
            }
        }
        lastFeedback = feedback
        if session.isComposing, !values.isEmpty, window != nil {
            candidates.updateStatus(status)
            candidates.update(
                candidates: values, pageIndex: session.pageIndex, pageCount: session.pageCount,
                input: session.buffer, warning: session.variantErrorMessage)
            candidates.onPage = { [weak self] delta in self?.session.page(delta); self?.refresh() }
            candidates.show(at: caret)
        } else { candidates.hide() }
    }

    func cancelComposition() { session.focusOut(); refresh() }
    func clear() { session.reset(); committed = ""; refresh() }

    /// 无按键的配置变更：即时应用到会话与候选窗（ADR-058）。
    func configChanged(_ key: String) {
        session.prepare()
        if let count = ImeConfig.int("candidate.count") { session.setPageSize(count) }
        if let mode = ImeConfig.string("mode"), session.mode != mode { session.setMode(mode) }
        refresh()
    }
}

final class PreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let session: ImeSession
    var window: NSWindow?
    var input: PreviewInput?
    var modeControl: NSPopUpButton?
    var previewMenu: PreviewInputMenu?
    let isolated: Bool
    init(session: ImeSession, isolated: Bool) { self.session = session; self.isolated = isolated }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = isolated ? "萤火虫 · 隔离验收" : "萤火虫 · 独立调试窗口"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let input = PreviewInput(session: session)
        input.persistModeChanges = isolated
        self.input = input
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = input
        input.isVerticallyResizable = true
        input.autoresizingMask = [.width]
        input.textContainer?.widthTracksTextView = true
        let hint = NSTextField(wrappingLabelWithString: "在下方末尾输入：wq → 你，nihao → 你好。空格/数字选字，回车提交字母，退格删码，Esc 取消。\n用于引擎、FFI 和候选窗调试；系统 IMK 集成仍需实机验收。")
        let status = NSTextField(wrappingLabelWithString: "组合：（空）")
        input.status = { status.stringValue = $0 }
        let mode = NSPopUpButton()
        modeControl = mode
        mode.addItems(withTitles: ["混输", "五笔", "拼音"])
        mode.target = self
        mode.action = #selector(changeMode(_:))
        let initial = ImeConfig.string("mode") ?? "mixed"
        mode.selectItem(at: ["mixed", "wubi", "pinyin"].firstIndex(of: initial) ?? 0)
        session.setMode(initial)
        let clear = NSButton(title: "清空", target: self, action: #selector(clearInput))
        let add = NSButton(title: "新增词条", target: self, action: #selector(addWord))
        let importButton = NSButton(title: "导入词库", target: self, action: #selector(importWords))
        let exportButton = NSButton(title: "导出词库", target: self, action: #selector(exportWords))
        let lookup = NSButton(title: "拼音反查", target: self, action: #selector(lookupPinyin))
        let settingsButton = NSButton(title: "偏好设置", target: self, action: #selector(openSettings))
        let controls = NSStackView(views: [NSTextField(labelWithString: "会话模式"), mode, clear, add, importButton, exportButton, lookup, settingsButton])
        controls.orientation = .horizontal
        var sections: [NSView] = [hint]
        if isolated {
            let menu = PreviewInputMenu(session: session)
            menu.onCancelComposition = { [weak input] in input?.cancelComposition() }
            menu.onChange = { [weak self] in self?.input?.refresh() }
            menu.onFailure = { [weak input] message in input?.status?(message) }
            menu.onClose = { [weak self] in self?.restoreInputFocus() }
            menu.onSettings = { [weak self] in self?.openSettings() }
            menu.onAbout = { AboutUI.show() }
            previewMenu = menu
            input.stateChanged = { [weak self] in self?.syncMenuControls() }
            let menuButton = NSButton(title: "输入法菜单", target: self, action: #selector(openInputMenu(_:)))
            let note = NSTextField(wrappingLabelWithString: "本轮使用独立配置和词库；关闭窗口结束，修改代码后重新运行。")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .secondaryLabelColor
            let menuRow = NSStackView(views: [menuButton, note])
            menuRow.orientation = .horizontal
            menuRow.spacing = 12
            sections.append(menuRow)
            menu.refresh()
        }
        sections += [controls, scroll, status]
        let stack = NSStackView(views: sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
                stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
                scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
                hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
                status.widthAnchor.constraint(equalTo: stack.widthAnchor),
                scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
            ])
        }
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(input)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func changeMode(_ sender: NSPopUpButton) {
        let next = InputStateMenu.modes[sender.indexOfSelectedItem].0
        if let previewMenu { previewMenu.selectMode(next) }
        else { input?.cancelComposition(); session.setMode(next) }
        restoreInputFocus()
    }
    private func syncMenuControls() {
        modeControl?.selectItem(at: InputStateMenu.modes.firstIndex(where: { $0.0 == session.mode }) ?? 0)
        previewMenu?.refresh()
    }
    private func restoreInputFocus() {
        if window?.isKeyWindow == true { window?.makeFirstResponder(input) }
    }
    @objc private func openInputMenu(_ sender: NSButton) {
        guard let previewMenu else { return }
        previewMenu.refresh()
        previewMenu.menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
    }
    @objc func lookupPinyin() { input?.cancelComposition(); LookupUI.show(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func openSettings() { input?.cancelComposition(); SettingsPanel.shared.show(session: session) }
    @objc func addWord() { input?.cancelComposition(); UserDictionaryUI.add(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func importWords() {
        input?.cancelComposition()
        let url = UserDictionaryUI.importFile(session)
        input?.refresh()
        if let url { input?.status?("用户词库已导入：\(url.path)") }
        window?.makeFirstResponder(input)
    }
    @objc func exportWords() {
        input?.cancelComposition()
        let url = UserDictionaryUI.exportFile(session)
        input?.refresh()
        if let url { input?.status?("用户词库已导出：\(url.path)") }
        window?.makeFirstResponder(input)
    }
    @objc func clearInput() { input?.clear(); window?.makeFirstResponder(input) }
    func windowDidResignKey(_ notification: Notification) { input?.cancelComposition() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

if Bundle.main.bundleIdentifier?.hasPrefix("cn.jokerhub.lampyris.isolatedpanel.") == true,
    !CommandLine.arguments.contains("--panel-isolation-probe") {
    fputs("BLOCKED：独立测试应用缺少隔离启动参数。\n", stderr)
    exit(3)
}
let data: URL
if CommandLine.arguments.count == 2 || CommandLine.arguments.count == 3 {
    data = URL(fileURLWithPath: CommandLine.arguments[CommandLine.arguments.count - 1])
} else if let resources = Bundle.main.resourceURL {
    data = resources.appendingPathComponent("data")
} else {
    fputs("请通过 dev-preview.sh 启动调试窗口。\n", stderr); exit(1)
}
guard let session = ImeSession(wubiPath: data.appendingPathComponent("wubi86-core.tsv").path,
    pinyinCharsPath: data.appendingPathComponent("pinyin-chars.tsv").path,
    pinyinWordsPath: data.appendingPathComponent("pinyin-core.tsv").path) else {
    fputs("无法加载真实词典，请检查 data/generated/。\n", stderr); exit(1)
}
_ = session.setVariantData(data.appendingPathComponent("variant-s2t.tsv").path)
let smoke = CommandLine.arguments.contains("--smoke-test")
let panelProbe = CommandLine.arguments.contains("--panel-isolation-probe")
let smokeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lampyris-preview-\(UUID().uuidString)")
if panelProbe {
    guard CommandLine.arguments.count == 5,
        ["normal", "failure", "INT", "TERM", "interactive"].contains(CommandLine.arguments[2])
    else { fputs("BLOCKED：隔离探针参数无效。\n", stderr); exit(3) }
    let root = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    guard root.lastPathComponent.hasPrefix("lampyris-panel-"),
        (try? String(contentsOf: root.appendingPathComponent("owner"), encoding: .utf8)) == root.lastPathComponent
    else { fputs("BLOCKED：测试目录身份无效。\n", stderr); exit(3) }
    ime_config_init(root.appendingPathComponent("config.toml").path)
} else if smoke {
    try FileManager.default.createDirectory(at: smokeDirectory, withIntermediateDirectories: true)
    ime_config_init(smokeDirectory.appendingPathComponent("config.toml").path)
} else { ime_config_init(ImePaths.configFile()) }
let app = NSApplication.shared
if smoke { app.setActivationPolicy(.prohibited) }
if panelProbe, CommandLine.arguments[2] != "interactive" {
    let mode = CommandLine.arguments[2]
    app.setActivationPolicy(.regular)
    session.prepare()
    guard ImeConfig.setString("mode", "wubi"),
        session.addWord(scheme: "wubi", code: "zz", text: "面板隔离测试词") == IME_OK
    else { fputs("FAIL：隔离数据初始化失败。\n", stderr); exit(1) }
    SettingsPanel.shared.prepare()
    let alert = NSAlert()
    alert.messageText = "萤火虫隔离面板验证"
    alert.informativeText = "仅使用测试进程自己的配置和词库。"
    alert.addButton(withTitle: "关闭测试面板")
    let panelTimer = Timer(timeInterval: 0.1, repeats: false) { _ in
        print("READY \(ProcessInfo.processInfo.processIdentifier)")
        fflush(stdout)
        if mode == "normal" { alert.buttons[0].performClick(nil) }
        else if mode == "failure" { exit(7) }
    }
    RunLoop.main.add(panelTimer, forMode: .modalPanel)
    guard alert.runModal() == .alertFirstButtonReturn else { exit(1) }
    print("PASS isolated-panel normal")
    exit(0)
}
if CommandLine.arguments.contains("--smoke-test") {
    // Native key representations must not alter a live FFI composition.
    func navigationEvent(_ key: UInt16, _ flags: NSEvent.ModifierFlags = [],
        characters: String = "\u{1f}") -> NSEvent {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: key) else { fatalError("Cannot create test event") }
        return event
    }
    session.setMode("wubi")
    for key: UInt16 in [123, 124, 125, 126] {
        _ = session.feed(27)
        guard !session.consumesCompositionNavigation(navigationEvent(key)) else { exit(1) }
        _ = session.feed(119); _ = session.feed(113)
        let candidates = session.candidates(limit: 9).map(\.text)
        for chars in ["\u{1f}", "\u{f701}", ""] {
            guard session.consumesCompositionNavigation(navigationEvent(key, characters: chars)),
                session.consumesCompositionNavigation(navigationEvent(key, .shift, characters: chars)),
                session.buffer == "wq", session.candidates(limit: 9).map(\.text) == candidates else { exit(1) }
        }
        for flags: NSEvent.ModifierFlags in [.command, .control, .option] {
            guard !session.consumesCompositionNavigation(navigationEvent(key, flags)) else { exit(1) }
        }
        guard !session.consumesCompositionNavigation(navigationEvent(116)),
            !session.consumesCompositionNavigation(navigationEvent(13)) else { exit(1) }
        _ = session.feed(8)
        guard session.buffer == "w" else { exit(1) }
        _ = session.feed(113)
        if case .committed("你") = session.feed(32) {} else { exit(1) }
        _ = session.feed(119); _ = session.feed(113)
        guard session.consumesCompositionNavigation(navigationEvent(key)) else { exit(1) }
        if case .committed("你") = session.feed(49) {} else { exit(1) }
        _ = session.feed(119); _ = session.feed(113); _ = session.feed(27)
        guard session.buffer.isEmpty else { exit(1) }
    }
    session.setMode("mixed")
    guard WubiHints.text(buffer: "wq", mode: "mixed", english: false, wildcard: false) == "键位提示：W 人 · Q 金",
        WubiHints.text(buffer: "nihao", mode: "pinyin", english: false, wildcard: false) == nil,
        WubiHints.text(buffer: "wq", mode: "wubi", english: true, wildcard: false) == nil,
        WubiHints.text(buffer: "z", mode: "wubi", english: false, wildcard: false) == nil,
        WubiHints.text(buffer: "z", mode: "wubi", english: false, wildcard: true) == "键位提示：Z 通配"
    else { fputs("五笔键位提示边界错误。\n", stderr); exit(1) }
    let geometry = CandidateWindow()
    let area = NSRect(x: 100, y: 100, width: 320, height: 500)
    let long = ImeCandidate(
        text: String(repeating: "长词条", count: 28), code: "", source: .codeTable, isPrefix: false)
    geometry.update(candidates: Array(repeating: long, count: 9),
        hint: WubiHints.text(buffer: "aaaa", mode: "wubi", english: false, wildcard: false))
    geometry.layout(at: NSRect(x: 410, y: 580, width: 1, height: 20), within: area)
    guard area.contains(geometry.frame), geometry.frame.height > 28 else { exit(1) }
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "好", code: "hao", source: .codeTable, isPrefix: false),
    ])
    geometry.layout(at: NSRect(x: 90, y: 90, width: 1, height: 20), within: area)
    guard area.contains(geometry.frame), geometry.frame.height < 60 else { exit(1) }
    // 候选来源显示（ADR-057）：混合来源页标注中文来源，单一来源页不标注。
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false),
    ])
    // 垂直居中（体验修复）：离屏渲染后文字带应与容器垂直居中（排除边框行列）。
    if let rep = geometry.renderSnapshotForTesting() {
        let h = rep.pixelsHigh
        var top = -1, bot = -1
        for y in 3..<(h - 3) {
            var cnt = 0
            for x in 8..<(rep.pixelsWide - 8) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                    c.redComponent < 0.4, c.greenComponent < 0.4, c.blueComponent < 0.4
                { cnt += 1 }
            }
            if cnt > 3 { if top < 0 { top = y }; bot = y }
        }
        let textCenter = Double(top + bot) / 2, boxCenter = Double(h) / 2
        let pixelsPerPoint = Double(h) / Double(geometry.frame.height)
        guard top >= 0, abs(textCenter - boxCenter) / pixelsPerPoint <= 2.5 else {
            fputs("候选窗文本未垂直居中：textCenter=\(textCenter) boxCenter=\(boxCenter)\n", stderr)
            exit(1)
        }
    }
    let mixedLabels = geometry.displayedCandidateTexts
    guard mixedLabels.count == 2, !mixedLabels[0].contains("五笔"), !mixedLabels[1].contains("拼") else {
        fputs("候选来源标签未按混输显示：\(mixedLabels)\n", stderr); exit(1)
    }
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)
    ])
    guard geometry.displayedCandidateTexts == ["1 你"] else {
        fputs("单一来源页不应标注来源：\(geometry.displayedCandidateTexts)\n", stderr); exit(1)
    }
    // 状态徽标 + 鼠标点选（T-MVP-06）。
    geometry.update(
        candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)],
        input: "wq")
    guard geometry.displayedInput == "wq" else {
        fputs("状态徽标未显示。\n", stderr); exit(1)
    }
    geometry.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)])
    guard geometry.displayedInput.isEmpty else { fputs("无状态时不应显示徽标。\n", stderr); exit(1) }
    var picked = -1
    geometry.onSelect = { picked = $0 }
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false),
    ])
    geometry.simulateClick(at: 1)
    guard picked == 1 else { fputs("鼠标点选回调索引错误：\(picked)\n", stderr); exit(1) }
    picked = -1
    guard geometry.accessiblePressForTesting(at: 0), picked == 0 else {
        fputs("辅助按下没有执行候选选择。\n", stderr); exit(1)
    }
    geometry.update(candidates: [])
    picked = -1
    guard !geometry.accessiblePressForTesting(at: 0), picked == -1 else {
        fputs("已移除候选仍能被辅助选择。\n", stderr); exit(1)
    }
    // 多屏/负坐标选屏（体验打磨）：副屏在左（负 X）时按相交面积选对屏；跨屏取交叠更大者。
    let primaryScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    let secondaryScreen = NSRect(x: -1280, y: 0, width: 1280, height: 1024)
    func screenIndex(_ caret: NSRect) -> Int? {
        CandidateWindow.bestScreenIndex(for: caret, among: [primaryScreen, secondaryScreen])
    }
    guard
        screenIndex(NSRect(x: 100, y: 100, width: 1, height: 20)) == 0,
        screenIndex(NSRect(x: -100, y: 100, width: 1, height: 20)) == 1,
        screenIndex(NSRect(x: 1910, y: 100, width: 20, height: 20)) == 0,
        screenIndex(NSRect(x: -15, y: 100, width: 20, height: 20)) == 1,
        screenIndex(NSRect(x: 9999, y: 9999, width: 1, height: 1)) == 0
    else {
        fputs("多屏选屏判定错误。\n", stderr); exit(1)
    }
    // 负坐标副屏 + 光标贴近顶部：候选窗仍完整落在该屏区域内。
    let negativeArea = NSRect(x: -1280, y: 0, width: 1280, height: 1024)
    geometry.update(candidates: (0..<9).map {
        ImeCandidate(text: "候选\($0)", code: "wq", source: .codeTable, isPrefix: false)
    })
    geometry.layout(at: NSRect(x: -20, y: 1010, width: 1, height: 20), within: negativeArea)
    guard negativeArea.contains(geometry.frame) else {
        fputs("副屏（负坐标）候选窗越界：\(geometry.frame)\n", stderr); exit(1)
    }
    // 光标贴近屏幕右下角：候选窗被推回区域内（高分屏 / 多屏边缘定位）。
    let cornerArea = NSRect(x: 0, y: 0, width: 1440, height: 900)
    geometry.update(candidates: (0..<9).map {
        ImeCandidate(text: "候选\($0)", code: "wq", source: .codeTable, isPrefix: false)
    })
    geometry.layout(at: NSRect(x: 1438, y: 2, width: 1, height: 20), within: cornerArea)
    guard cornerArea.contains(geometry.frame) else {
        fputs("右下角候选窗越界：\(geometry.frame)\n", stderr); exit(1)
    }
    // 悬停高亮（体验打磨）：进入/离开切换，候选刷新后复位。
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false),
    ])
    geometry.simulateHover(at: 0, true)
    guard geometry.isHovered(at: 0), !geometry.isHovered(at: 1) else {
        fputs("悬停高亮未按候选切换。\n", stderr); exit(1)
    }
    guard geometry.isHoverRenderable(at: 0) else {
        fputs("悬停高亮图层缺失，高亮会静默失效。\n", stderr); exit(1)
    }
    geometry.simulateHover(at: 0, false)
    guard !geometry.isHovered(at: 0) else {
        fputs("离开候选后悬停高亮未清除。\n", stderr); exit(1)
    }
    geometry.simulateHover(at: 1, true)
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false),
    ])
    guard !geometry.isHovered(at: 1) else {
        fputs("候选刷新后应复位悬停高亮。\n", stderr); exit(1)
    }
    // 数据加载失败可诊断：缺文件必须返回 nil，而不是静默样本兜底（ADR-063）。
    guard
        ImeSession(
            wubiPath: "/nonexistent-lampyris.tsv", pinyinCharsPath: nil, pinyinWordsPath: nil)
            == nil
    else {
        fputs("缺失码表应返回 nil。\n", stderr); exit(1)
    }
    session.setMode("mixed")
    let view = PreviewInput(session: session)
    ConfigWatcher.shared.observe(owner: view) { [weak view] key in view?.configChanged(key) }
    func keys(_ text: String, flags: NSEvent.ModifierFlags = []) {
        for scalar in text.unicodeScalars {
            guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: String(scalar),
                charactersIgnoringModifiers: String(scalar), isARepeat: false, keyCode: 0) else {
                fputs("无法创建测试按键。\n", stderr); exit(1)
            }
            view.keyDown(with: event)
        }
    }
    func check(_ expected: String) {
        guard view.string == expected else {
            fputs("预览冒烟失败：预期 \(expected)，实际 \(view.string)\n", stderr); exit(1)
        }
    }
    keys("a")
    let aFirstPage = session.candidates(limit: 9).map(\.text)
    guard session.pageCount > 1 else { fputs("a应有多页候选。\n", stderr); exit(1) }
    keys("=")
    guard session.pageIndex == 1, session.candidates(limit: 9).map(\.text) != aFirstPage else { exit(1) }
    view.clear()
    keys("wq"); check("wq")
    guard session.pageCount > 1 else { fputs("缺少分页候选。\n", stderr); exit(1) }
    let firstPage = session.candidates(limit: 9).map(\.text)
    keys("=")
    guard session.pageIndex == 1, session.candidates(limit: 9).map(\.text) != firstPage else { exit(1) }
    keys("-")
    guard session.pageIndex == 0 else { exit(1) }
    guard session.candidates(limit: 1).first?.text == "你" else { exit(1) }
    guard session.candidates(limit: 1).first?.source == .codeTable else {
        fputs("五笔候选来源未贯穿到宿主。\n", stderr); exit(1)
    }
    keys(" nihao "); check("你你好")
    keys("wq\u{7f}"); check("你你好w")
    keys("\u{1b}"); check("你你好")
    keys("wq2"); check("你你好像")
    keys("wq\r"); check("你你好像wq")
    view.clear(); check("")
    session.setMode("pinyin")
    keys("nihao")
    guard session.candidates(limit: 9).first?.source == .pinyin else {
        fputs("拼音候选来源未贯穿到宿主。\n", stderr); exit(1)
    }
    keys(" "); check("你好")
    view.clear(); keys("\".\""); check("“。”")
    session.focusOut(); view.clear(); keys("\""); check("“")
    // 中英：默认“单独 Shift”（flagsChanged 语义）。
    _ = session.shiftTransition(isDown: true); _ = session.shiftTransition(isDown: false)
    view.clear(); keys("nihao"); check("nihao")
    // 按住 Shift 期间有其它键 → 抬起不切换中英。
    _ = session.shiftTransition(isDown: true)
    session.markKeyWhileShift()
    let englishBefore = session.isEnglish
    _ = session.shiftTransition(isDown: false)
    guard session.isEnglish == englishBefore else { exit(1) }
    // Shift 期间有其它修饰键（Ctrl/Option/Command）→ 抬起也不切换中英（避免 Ctrl+Shift+M 误切）。
    _ = session.shiftTransition(isDown: true, otherModifier: true)
    let englishBeforeCombo = session.isEnglish
    _ = session.shiftTransition(isDown: false, otherModifier: true)
    guard session.isEnglish == englishBeforeCombo else {
        fputs("修饰键组合不应触发中英切换。\n", stderr); exit(1)
    }
    // 全/半角：默认 Option+F（ADR-210；此刻中英为“英”，故 A1 → Ａ１）。
    keys("f", flags: [.option]); view.clear(); keys("A1"); check("Ａ１")
    keys("f", flags: [.option])
    // 中英切回中文。
    _ = session.shiftTransition(isDown: true); _ = session.shiftTransition(isDown: false)
    guard !session.isEnglish else { exit(1) }
    // 模式：默认 alt+m。
    keys("m", flags: [.option])
    guard session.mode == "mixed" else { exit(1) }
    // 中英标点：默认 alt+p（写回配置）。
    let punctuationBefore = ImeConfig.string("input.punctuation")
    keys("p", flags: [.option])
    guard ImeConfig.string("input.punctuation") != punctuationBefore else {
        fputs("Option+P 未切换中英标点。\n", stderr); exit(1)
    }
    keys("p", flags: [.option])
    guard ImeConfig.string("input.punctuation") == punctuationBefore else { exit(1) }
    // 组合态 , / . 翻页（对齐搜狗/微信）。
    session.setMode("mixed"); view.clear(); keys("a")
    guard session.pageCount > 1 else { fputs("a 应有多页候选。\n", stderr); exit(1) }
    let aPage = session.candidates(limit: 9).map(\.text)
    keys(".")
    guard session.pageIndex == 1, session.candidates(limit: 9).map(\.text) != aPage else { exit(1) }
    keys(",")
    guard session.pageIndex == 0 else { exit(1) }
    // 简/繁：默认 Option+T 切换后上屏输出繁体（T-P2-01/ADR-208/209）。
    session.setMode("wubi"); view.clear()
    _ = ImeConfig.setToml("wubi.auto_commit", "false"); session.prepare()
    let variantBefore = ImeConfig.string("input.chinese_variant")
    keys("t", flags: [.option])
    guard ImeConfig.string("input.chinese_variant") != variantBefore else {
        fputs("Option+T 未切换简繁。\n", stderr); exit(1)
    }
    keys("kwwl"); keys(" "); check("中華人民共和國")
    keys("t", flags: [.option])
    guard ImeConfig.string("input.chinese_variant") == variantBefore else { exit(1) }
    _ = ImeConfig.setToml("wubi.auto_commit", "true"); session.prepare()
    session.setMode("mixed")
    guard ImeConfig.setString("appearance.theme", "dark") else { exit(1) }
    guard ImeConfig.string("appearance.theme") == "dark" else { exit(1) }
    let qaDirectory = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("qa-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: qaDirectory, withIntermediateDirectories: false)
    func saveQA(_ image: NSBitmapImageRep?, _ name: String) {
        guard let bytes = image?.representation(using: .png, properties: [:]) else { fputs("视觉证据生成失败：\(name)\n", stderr); exit(1) }
        do { try bytes.write(to: qaDirectory.appendingPathComponent(name), options: .withoutOverwriting) }
        catch { fputs("视觉证据保存失败：\(error)\n", stderr); exit(1) }
    }
    // Semantic text colors are composited over the actual painted backgrounds.
    for theme in ["light", "dark"] {
        guard ImeConfig.setString("appearance.theme", theme),
            let appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        else { exit(1) }
        appearance.performAsCurrentDrawingAppearance {
            let surfaces: [(String, NSColor, NSColor)] = [
                ("候选正文", .labelColor, .windowBackgroundColor),
                ("候选来源/状态", ImeAppearance.secondaryText, .windowBackgroundColor),
                ("悬停正文", .labelColor, ImeAppearance.hoverBackground()),
                ("悬停来源", ImeAppearance.secondaryText, ImeAppearance.hoverBackground()),
                ("设置说明", ImeAppearance.secondaryText, .windowBackgroundColor),
                ("错误状态", ImeAppearance.errorText, .windowBackgroundColor),
            ]
            for (surface, foreground, background) in surfaces {
                let ratio = ImeAppearance.contrast(foreground, over: background)
                guard ratio >= 4.5 else {
                    fputs("\(surface)在\(theme)主题下合成对比度不足：\(ratio)。\n", stderr); exit(1)
                }
            }
        }
        geometry.update(candidates: [
            ImeCandidate(text: "你好世界", code: "wq", source: .codeTable, isPrefix: false),
            ImeCandidate(text: "混输", code: "ni", source: .pinyin, isPrefix: false),
        ], input: "wq", hint: WubiHints.text(buffer: "wq", mode: "mixed", english: false, wildcard: false))
        saveQA(geometry.renderSnapshotForTesting(), "candidate-\(theme).png")
        saveQA(SettingsPanel.shared.renderSnapshotForTesting(appearance: appearance), "settings-\(theme).png")
        saveQA(SettingsPanel.shared.renderLongErrorForTesting(appearance: appearance), "settings-error-\(theme).png")
        saveQA(SettingsPanel.shared.renderMinimumSizeForTesting(appearance: appearance), "settings-minimum-\(theme).png")
    }
    func pump(until condition: () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return condition()
    }
    // 外部改配置：正在输入的候选窗即时按新设置变化，无需再按键（ADR-058 / MVP-03）。
    let external = smokeDirectory.appendingPathComponent("config.toml")
    view.clear(); keys("a")
    guard session.isComposing, session.candidates(limit: 9).count > 3 else {
        fputs("默认候选数应大于 3。\n", stderr); exit(1)
    }
    try "[candidate]\ncount = 3\n".write(to: external, atomically: true, encoding: .utf8)
    guard pump(until: { session.candidates(limit: 9).count == 3 }) else {
        fputs("候选数未即时刷新。\n", stderr); exit(1)
    }
    try "mode = \"wubi\"\n[candidate]\ncount = 3\n".write(to: external, atomically: true, encoding: .utf8)
    guard pump(until: { session.mode == "wubi" }) else {
        fputs("模式未即时刷新。\n", stderr); exit(1)
    }
    // 配置错误：保留上一份有效设置、暴露可读错误；修好后清除（ADR-059 / MVP-04）。
    try "mode = [oops\n".write(to: external, atomically: true, encoding: .utf8)
    guard pump(until: { ImeConfig.errorMessage() != nil }) else {
        fputs("坏配置未产生可见错误。\n", stderr); exit(1)
    }
    guard ImeConfig.string("mode") == "wubi" else {
        fputs("坏配置应保留上一份有效设置。\n", stderr); exit(1)
    }
    try "mode = \"mixed\"\n[candidate]\ncount = 3\n".write(to: external, atomically: true, encoding: .utf8)
    guard pump(until: { ImeConfig.errorMessage() == nil }) else {
        fputs("修复后配置错误未清除。\n", stderr); exit(1)
    }
    session.setMode("mixed"); view.clear(); keys("wq")
    guard session.candidates(limit: 9).count == 3 else { exit(1) }
    guard session.reverseLookup("你好") == "ni hao", session.reverseLookup("🙂") == nil else { exit(1) }
    guard ImeConfig.setToml("candidate.count", "9"), ImeConfig.setToml("pinyin.fuzzy", "true") else { exit(1) }
    session.prepare()
    session.setPageSize(9)
    session.setMode("pinyin")
    for (input, target) in [("nihao", "你好"), ("nh", "你好"), ("zhongguo", "中国"),
        ("zg", "中国"), ("shijie", "世界"), ("xiexie", "谢谢"),
        ("zongguo", "中国"), ("sijie", "世界"), ("sisi", "试试")] {
        session.reset()
        for letter in input.utf8 { _ = session.feed(UInt32(letter)) }
        guard session.candidates(limit: 9).contains(where: { $0.text == target }) else {
            fputs("核心拼音质量回归失败：\(input)未在前9项命中\(target)。\n", stderr); exit(1)
        }
    }
    session.reset()
    guard ImeConfig.setToml("pinyin.fuzzy", "false"), ImeConfig.setToml("candidate.count", "3") else { exit(1) }
    session.prepare()
    session.setPageSize(3)
    session.setMode("mixed")
    guard session.addWord(scheme: "wubi", code: "zz", text: "离线测试词") == IME_OK else { exit(1) }
    guard session.addWord(scheme: "wubi", code: "zz", text: "待删测试词") == IME_OK,
        session.removeWord(scheme: "wubi", code: "zz", text: "待删测试词") == IME_OK,
        session.removeWord(scheme: "wubi", code: "zz", text: "待删测试词") == IME_ERR_NOT_FOUND,
        UserDictionaryUI.entryError(IME_ERR_INVALID_INPUT, code: "AB", text: "词").contains("小写"),
        UserDictionaryUI.entryError(IME_ERR_NOT_FOUND, code: "ab", text: "词").contains("未找到")
    else { fputs("用户词条精确删除或校验反馈失败。\n", stderr); exit(1) }
    view.clear(); keys("zz "); check("离线测试词")
    let exported = smokeDirectory.appendingPathComponent("export.tsv")
    guard session.exportDictionary(exported.path) == IME_OK else { exit(1) }
    guard session.importDictionary(exported.path) == IME_OK else { exit(1) }
    let bad = smokeDirectory.appendingPathComponent("bad.tsv")
    try "broken".write(to: bad, atomically: true, encoding: .utf8)
    guard session.importDictionary(bad.path) != IME_OK else { exit(1) }
    guard let importError = session.dictionaryOperationError,
        importError.contains(bad.path), importError.contains("第1行"),
        session.importDictionary(exported.path) == IME_OK, session.dictionaryOperationError == nil
    else { fputs("词库导入错误定位或恢复清除失败。\n", stderr); exit(1) }
    guard let restored = ImeSession(wubiPath: data.appendingPathComponent("wubi86-core.tsv").path,
        pinyinCharsPath: data.appendingPathComponent("pinyin-chars.tsv").path,
        pinyinWordsPath: data.appendingPathComponent("pinyin-core.tsv").path) else { exit(1) }
    restored.setMode("mixed"); _ = restored.feed(122); _ = restored.feed(122)
    guard restored.candidates(limit: 1).first?.text == "离线测试词" else { exit(1) }
    // 设置面板（ADR-070）：Schema 驱动、界面零硬编码。
    let settingsOptions = SettingsSchema.options()
    guard settingsOptions.count == 19 else {
        fputs("设置项数量应为 19，实际 \(settingsOptions.count)。\n", stderr); exit(1)
    }
    guard settingsOptions.allSatisfy({ !$0.title.isEmpty && !$0.doc.isEmpty }) else {
        fputs("设置项缺标题或说明。\n", stderr); exit(1)
    }
    guard settingsOptions.allSatisfy({ option in
        if case .choice(let values, let labels) = option.kind {
            return !values.isEmpty && values.count == labels.count
        }
        return true
    }) else {
        for option in settingsOptions {
            if case .choice(let values, let labels) = option.kind, values.count != labels.count {
                fputs("枚举错位：\(option.key) values=\(values) labels=\(labels)\n", stderr)
            }
        }
        exit(1)
    }
    SettingsPanel.shared.prepare()
    guard SettingsPanel.shared.rowCount == settingsOptions.count else {
        fputs("设置面板行数与 Schema 不一致。\n", stderr); exit(1)
    }
    InfoWindow.prepareThemeForTesting()
    let themes: [(String, NSAppearance.Name?)] = [("dark", .darkAqua), ("light", .aqua), ("auto", nil)]
    for (value, expected) in themes {
        guard ImeConfig.setString("appearance.theme", value), pump(until: {
            SettingsPanel.shared.configuredAppearanceForTesting == expected &&
                InfoWindow.configuredAppearanceForTesting == expected
        }) else { fputs("设置/信息窗口未即时应用配置主题。\n", stderr); exit(1) }
        view.candidates.refreshAppearance()
        guard view.candidates.configuredAppearanceForTesting == expected else {
            fputs("候选主题与配置不一致。\n", stderr); exit(1)
        }
    }
    let displayedKeys = SettingsPanel.shared.displayedOptionKeys
    guard displayedKeys.count == settingsOptions.count,
        Set(displayedKeys) == Set(settingsOptions.map(\.key)),
        SettingsPanel.shared.minimumContentSize.width >= 520,
        SettingsPanel.shared.minimumContentSize.height >= 440
    else { fputs("设置分组或窗口约束不符。\n", stderr); exit(1) }
    // 面板（ADR-077/080）：设置/词库 两个分区。
    guard SettingsPanel.shared.sectionCount == 4 else {
        fputs("设置面板分区数应为 4，实际 \(SettingsPanel.shared.sectionCount)。\n", stderr); exit(1)
    }
    guard AboutUI.text().contains("GPL-3.0") else {
        fputs("版本信息缺失。\n", stderr); exit(1)
    }
    // Real-data fuzzy changes refresh an existing composition without new keys.
    guard ImeConfig.setString("mode", "pinyin"), ImeConfig.setToml("pinyin.fuzzy", "false") else { exit(1) }
    session.setMode("pinyin"); session.prepare(); view.clear(); keys("zongguo")
    let exactCandidates = session.candidates(limit: 9).map(\.text)
    guard session.buffer == "zongguo", ImeConfig.setToml("pinyin.fuzzy", "true") else { exit(1) }
    view.configChanged("pinyin.fuzzy")
    guard session.buffer == "zongguo", session.isComposing,
        session.candidates(limit: 9).map(\.text) != exactCandidates
    else { fputs("组合中模糊音配置未重算候选。\n", stderr); exit(1) }
    session.page(1)
    let preservedPage = session.pageIndex
    view.configChanged("appearance.theme")
    guard session.pageIndex == preservedPage, session.buffer == "zongguo" else { exit(1) }
    guard ImeConfig.setToml("pinyin.fuzzy", "false"), ImeConfig.setString("mode", "mixed") else { exit(1) }
    view.configChanged("pinyin.fuzzy"); session.setMode("mixed"); view.clear()
    // Width preference changes replace only the temporary width override.
    guard ImeConfig.setToml("input.full_width", "false") else { exit(1) }
    session.prepare(); session.toggleWidth()
    guard session.isFullWidth else { exit(1) }
    session.prepare()
    guard session.isFullWidth, ImeConfig.setToml("input.full_width", "true") else { exit(1) }
    session.prepare()
    guard session.isFullWidth, ImeConfig.setToml("input.full_width", "false") else { exit(1) }
    session.prepare()
    guard !session.isFullWidth else { exit(1) }
    view.clear(); keys("1"); check("1")
    // Broken lazy variant resources remain visible and never claim effective traditional output.
    let invalidVariant = smokeDirectory.appendingPathComponent("invalid-variant.tsv")
    try "broken".write(to: invalidVariant, atomically: true, encoding: .utf8)
    guard ImeConfig.setString("input.chinese_variant", "traditional") else { exit(1) }
    session.setVariantData(invalidVariant.path); session.prepare()
    guard session.variantError != IME_OK, !session.isTraditional,
        session.variantErrorMessage != nil, session.isComposing == false
    else { exit(1) }
    guard ImeConfig.setString("input.chinese_variant", "simplified") else { exit(1) }
    session.prepare(); session.setVariantData(data.appendingPathComponent("variant-s2t.tsv").path)
    guard ImeConfig.setString("input.chinese_variant", "traditional") else { exit(1) }
    session.prepare()
    guard session.variantError == IME_OK, session.isTraditional else { exit(1) }
    guard ImeConfig.setString("input.chinese_variant", "simplified") else { exit(1) }
    session.prepare()
    // A locked test config rejects persistence but consumes recognized shortcuts.
    let previousMode = session.mode
    let previousPunctuation = ImeConfig.string("input.punctuation")
    let previousVariant = ImeConfig.string("input.chinese_variant")
    let lockedBytes = try Data(contentsOf: external)
    let configLock = URL(fileURLWithPath: external.path + ".lock")
    try Data("test lock".utf8).write(to: configLock, options: .withoutOverwriting)
    for (text, flags) in [("m", NSEvent.ModifierFlags([.option])), ("p", [.option]), ("t", [.option])] {
        guard let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0),
            session.shortcut(event, persistMode: true) == .failed,
            ImeConfig.errorMessage()?.contains("被锁定") == true
        else { fputs("锁占用时快捷键失败契约不符。\n", stderr); exit(1) }
    }
    guard session.mode == previousMode,
        ImeConfig.string("input.punctuation") == previousPunctuation,
        ImeConfig.string("input.chinese_variant") == previousVariant,
        try Data(contentsOf: external) == lockedBytes
    else { exit(1) }
    try FileManager.default.removeItem(at: configLock)
    guard session.togglePunctuation(), ImeConfig.errorMessage() == nil else { exit(1) }
    // All controllers share an error cycle; recovery permits a fresh notice.
    let errorGate = ErrorNoticeGate()
    guard errorGate.claim(channel: "configuration", message: "locked"),
        !errorGate.claim(channel: "configuration", message: "locked"),
        errorGate.claim(channel: "configuration", message: "bad syntax"),
        !errorGate.claim(channel: "configuration", message: "locked"),
        errorGate.claim(channel: "resources", message: "locked"),
        !errorGate.claim(channel: "configuration", message: nil),
        errorGate.claim(channel: "configuration", message: "locked")
    else { fputs("进程错误提示门控不符。\n", stderr); exit(1) }
    var currentNotice: String? = "locked"
    var displayedNotices: [String] = []
    let presenter = ProcessErrorPresenter { _, message in displayedNotices.append(message) }
    for _ in 0..<3 {
        presenter.update(channel: "test", title: "test", current: { currentNotice })
    }
    guard pump(until: { displayedNotices.count == 1 }), displayedNotices == ["locked"] else { exit(1) }
    currentNotice = nil
    presenter.update(channel: "test", title: "test", current: { currentNotice })
    currentNotice = "old"
    presenter.update(channel: "test", title: "test", current: { currentNotice })
    currentNotice = "new"
    presenter.update(channel: "test", title: "test", current: { currentNotice })
    guard pump(until: { displayedNotices.count == 2 }), displayedNotices == ["locked", "new"] else { exit(1) }
    // Typed shortcut contract: runtime and menu consume the same canonical ABI.
    guard ImeConfig.setString("hotkey.toggle_mode", "CONTROL + OPTION + M") else { exit(1) }
    let normalizedHotkey = ImeConfig.hotkey("hotkey.toggle_mode")
    guard normalizedHotkey.kind == 2, normalizedHotkey.equivalent == "m",
        normalizedHotkey.modifiers == [.control, .option],
        ImeConfig.string("hotkey.toggle_mode") == "ctrl+alt+m",
        !ImeConfig.setString("hotkey.toggle_mode", "banana"),
        !ImeConfig.setString("hotkey.toggle_mode", "alt+f"),
        ImeConfig.setString("hotkey.toggle_mode", "none"),
        ImeConfig.hotkey("hotkey.toggle_mode").kind == 0
    else { fputs("快捷键规范/非法值/冲突校验失败。\n", stderr); exit(1) }
    // 写回往返：设置面板走的正是这条唯一路径（ime_config_set）。
    guard ImeConfig.setToml("candidate.count", "5"), ImeConfig.int("candidate.count") == 5 else {
        fputs("设置写回候选数失败。\n", stderr); exit(1)
    }
    guard ImeConfig.setString("appearance.theme", "dark"),
        ImeConfig.string("appearance.theme") == "dark"
    else {
        fputs("设置写回主题失败。\n", stderr); exit(1)
    }
    // 反馈入口（ADR-071）：静态公开链接、诊断信息不含隐私。
    guard FeedbackUI.issuesURL.absoluteString.hasPrefix(
        "https://github.com/EasyIndie/EasyInputMethod/")
    else {
        fputs("反馈链接不是项目公开地址。\n", stderr); exit(1)
    }
    let diagnostics = FeedbackUI.diagnostics()
    let feedbackPasteboard = NSPasteboard(name: NSPasteboard.Name("lampyris-feedback-test-\(UUID().uuidString)"))
    guard InfoWindow.copy(diagnostics, to: feedbackPasteboard),
        feedbackPasteboard.string(forType: .string) == diagnostics
    else { fputs("诊断复制失败。\n", stderr); exit(1) }
    feedbackPasteboard.releaseGlobally()
    let failedOpen = InfoWindow.testOpenResult(FeedbackUI.issuesURL, succeeded: false)
    let successfulOpen = InfoWindow.testOpenResult(FeedbackUI.issuesURL, succeeded: true)
    guard failedOpen.0.contains("打开失败"), failedOpen.1 == FeedbackUI.issuesURL.absoluteString,
        failedOpen.2, successfulOpen.1.isEmpty, !successfulOpen.2
    else { fputs("渠道打开结果缺少地址回退。\n", stderr); exit(1) }
    guard diagnostics.contains("Lampyris"), diagnostics.contains("系统："),
        diagnostics.contains("架构：")
    else {
        fputs("诊断信息缺少版本/系统/架构。\n", stderr); exit(1)
    }
    try? FileManager.default.removeItem(at: smokeDirectory)
    print("视觉证据：\(qaDirectory.path)")
    print("✅ 预览冒烟通过：文本渲染、候选、五笔/拼音、数字选字/回车字母、退格/Esc、清空。")
    exit(0)
}
app.setActivationPolicy(.regular)
let menu = NSMenu()
let root = NSMenuItem()
let submenu = NSMenu()
submenu.addItem(withTitle: "退出调试窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
root.submenu = submenu
menu.addItem(root)
app.mainMenu = menu
let delegate = PreviewDelegate(session: session, isolated: panelProbe)
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
