import Cocoa
import ime

// Local preview adapter; engine state and candidates come from the production FFI.
final class PreviewInput: NSTextView {
    let session: ImeSession
    let candidates = CandidateWindow()
    private var committed = ""
    private let previewStorage = NSTextStorage()
    var status: ((String) -> Void)?

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
        if session.shortcut(event, persistMode: false) { refresh(); return }
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
        if session.shiftTransition(isDown: flags.contains(.shift), otherModifier: other) {
            refresh()
        }
    }

    func refresh() {
        let content = NSMutableAttributedString(string: committed, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        content.append(NSAttributedString(string: session.buffer, attributes: [
            .font: NSFont.systemFont(ofSize: 24), .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.controlAccentColor,
        ]))
        textStorage?.setAttributedString(content)
        setSelectedRange(NSRange(location: content.length, length: 0))
        let values = session.candidates(limit: ImeConfig.int("candidate.count") ?? 9)
        let summary = values.map { "\($0.text)[\($0.source.label)]" }.joined(separator: " · ")
        status?("词库：\(session.dictionaryError == IME_OK ? "正常" : "读写失败")   页：\(session.pageIndex + 1)/\(session.pageCount)   组合：\(session.buffer.isEmpty ? "（空）" : session.buffer)   候选：\(summary)")
        if session.isComposing, !values.isEmpty, window != nil {
            let badge = ["mixed": "混输", "wubi": "五笔", "pinyin": "拼"][session.mode] ?? session.mode
            candidates.update(
                candidates: values, pageIndex: session.pageIndex, pageCount: session.pageCount,
                status: session.isFullWidth ? "\(badge)·全" : badge)
            let caret = firstRect(forCharacterRange: NSRange(location: content.length, length: 0), actualRange: nil)
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
    init(session: ImeSession) { self.session = session }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 430),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "萤火虫 · 独立调试窗口"
        window.delegate = self
        window.isReleasedWhenClosed = false
        let input = PreviewInput(session: session)
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
        let stack = NSStackView(views: [hint, controls, scroll, status])
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
        input?.cancelComposition()
        session.setMode(["mixed", "wubi", "pinyin"][sender.indexOfSelectedItem])
        window?.makeFirstResponder(input)
    }
    @objc func lookupPinyin() { input?.cancelComposition(); LookupUI.show(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func openSettings() { input?.cancelComposition(); SettingsPanel.shared.show(session: session) }
    @objc func addWord() { input?.cancelComposition(); UserDictionaryUI.add(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func importWords() { input?.cancelComposition(); UserDictionaryUI.importFile(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func exportWords() { input?.cancelComposition(); UserDictionaryUI.exportFile(session); input?.refresh(); window?.makeFirstResponder(input) }
    @objc func clearInput() { input?.clear(); window?.makeFirstResponder(input) }
    func windowDidResignKey(_ notification: Notification) { input?.cancelComposition() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
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
let smokeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("lampyris-preview-\(UUID().uuidString)")
if smoke {
    try FileManager.default.createDirectory(at: smokeDirectory, withIntermediateDirectories: true)
    ime_config_init(smokeDirectory.appendingPathComponent("config.toml").path)
} else { ime_config_init(ImePaths.configFile()) }
let app = NSApplication.shared
if CommandLine.arguments.contains("--smoke-test") {
    let geometry = CandidateWindow()
    let area = NSRect(x: 100, y: 100, width: 320, height: 500)
    let long = ImeCandidate(
        text: String(repeating: "长词条", count: 28), code: "", source: .codeTable, isPrefix: false)
    geometry.update(candidates: Array(repeating: long, count: 9))
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
    let mixedLabels = geometry.displayedCandidateTexts
    guard mixedLabels.count == 2, mixedLabels[0].contains("五笔"), mixedLabels[1].contains("拼") else {
        fputs("候选来源标签未按混输显示：\(mixedLabels)\n", stderr); exit(1)
    }
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)
    ])
    guard geometry.displayedCandidateTexts == ["1.你"] else {
        fputs("单一来源页不应标注来源：\(geometry.displayedCandidateTexts)\n", stderr); exit(1)
    }
    // 状态徽标 + 鼠标点选（T-MVP-06）。
    geometry.update(
        candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)],
        status: "五笔·全")
    guard geometry.displayedStatus == "五笔·全" else {
        fputs("状态徽标未显示。\n", stderr); exit(1)
    }
    geometry.update(candidates: [ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false)])
    guard geometry.displayedStatus == nil else { fputs("无状态时不应显示徽标。\n", stderr); exit(1) }
    var picked = -1
    geometry.onSelect = { picked = $0 }
    geometry.update(candidates: [
        ImeCandidate(text: "你", code: "wq", source: .codeTable, isPrefix: false),
        ImeCandidate(text: "尼", code: "ni", source: .pinyin, isPrefix: false),
    ])
    geometry.simulateClick(at: 1)
    guard picked == 1 else { fputs("鼠标点选回调索引错误：\(picked)\n", stderr); exit(1) }
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
    // 全/半角：默认 Shift+Space（此刻中英为“英”，故 A1 → Ａ１）。
    keys(" ", flags: [.shift]); view.clear(); keys("A1"); check("Ａ１")
    keys(" ", flags: [.shift])
    // 中英切回中文。
    _ = session.shiftTransition(isDown: true); _ = session.shiftTransition(isDown: false)
    guard !session.isEnglish else { exit(1) }
    // 模式：默认 ctrl+shift+m。
    keys("m", flags: [.control, .shift])
    guard session.mode == "mixed" else { exit(1) }
    // 中英标点：默认 ctrl+.（写回配置）。
    let punctuationBefore = ImeConfig.string("input.punctuation")
    keys(".", flags: [.control])
    guard ImeConfig.string("input.punctuation") != punctuationBefore else {
        fputs("Ctrl+. 未切换中英标点。\n", stderr); exit(1)
    }
    keys(".", flags: [.control])
    guard ImeConfig.string("input.punctuation") == punctuationBefore else { exit(1) }
    // 组合态 , / . 翻页（对齐搜狗/微信）。
    session.setMode("mixed"); view.clear(); keys("a")
    guard session.pageCount > 1 else { fputs("a 应有多页候选。\n", stderr); exit(1) }
    let aPage = session.candidates(limit: 9).map(\.text)
    keys(".")
    guard session.pageIndex == 1, session.candidates(limit: 9).map(\.text) != aPage else { exit(1) }
    keys(",")
    guard session.pageIndex == 0 else { exit(1) }
    // 简/繁：默认 Ctrl+Shift+F 切换后上屏输出繁体（T-P2-01）。
    session.setMode("wubi"); view.clear()
    _ = ImeConfig.setToml("wubi.auto_commit", "false"); session.prepare()
    let variantBefore = ImeConfig.string("input.chinese_variant")
    keys("f", flags: [.control, .shift])
    guard ImeConfig.string("input.chinese_variant") != variantBefore else {
        fputs("Ctrl+Shift+F 未切换简繁。\n", stderr); exit(1)
    }
    keys("kwwl"); keys(" "); check("中華人民共和國")
    keys("f", flags: [.control, .shift])
    guard ImeConfig.string("input.chinese_variant") == variantBefore else { exit(1) }
    _ = ImeConfig.setToml("wubi.auto_commit", "true"); session.prepare()
    session.setMode("mixed")
    guard ImeConfig.setString("appearance.theme", "dark") else { exit(1) }
    guard ImeConfig.string("appearance.theme") == "dark" else { exit(1) }
    // 亮/暗主题可读性（⑬）：候选窗与设置面板在两种外观下离屏渲染，前景/背景对比度应达 WCAG AA（≥4.5）。
    func srgbLuminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB) ?? color
        func lin(_ v: CGFloat) -> CGFloat { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.redComponent) + 0.7152 * lin(c.greenComponent) + 0.0722 * lin(c.blueComponent)
    }
    func assertReadable(_ surface: String, _ theme: String, _ rep: NSBitmapImageRep?) {
        guard let rep else {
            fputs("\(surface) 在 \(theme) 主题下渲染失败。\n", stderr); exit(1)
        }
        var lo = CGFloat.greatestFiniteMagnitude, hi = -CGFloat.greatestFiniteMagnitude
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                if let c = rep.colorAt(x: x, y: y) {
                    let l = srgbLuminance(c)
                    lo = min(lo, l); hi = max(hi, l)
                }
            }
        }
        let ratio = lo.isFinite && hi.isFinite ? (hi + 0.05) / (lo + 0.05) : 0
        guard ratio >= 4.5 else {
            fputs("\(surface) 在 \(theme) 主题对比度不足：\(ratio)。\n", stderr); exit(1)
        }
    }
    for theme in ["light", "dark"] {
        guard ImeConfig.setString("appearance.theme", theme) else { exit(1) }
        geometry.update(candidates: [
            ImeCandidate(text: "你好世界", code: "wq", source: .codeTable, isPrefix: false),
            ImeCandidate(text: "混输", code: "ni", source: .pinyin, isPrefix: false),
        ], status: "五笔·全")
        assertReadable("候选窗", theme, geometry.renderSnapshotForTesting())
        let appearance = NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)
        assertReadable("设置面板", theme, SettingsPanel.shared.renderSnapshotForTesting(appearance: appearance!))
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
    guard session.addWord(scheme: "wubi", code: "zz", text: "离线测试词") == IME_OK else { exit(1) }
    view.clear(); keys("zz "); check("离线测试词")
    let exported = smokeDirectory.appendingPathComponent("export.tsv")
    guard session.exportDictionary(exported.path) == IME_OK else { exit(1) }
    guard session.importDictionary(exported.path) == IME_OK else { exit(1) }
    let bad = smokeDirectory.appendingPathComponent("bad.tsv")
    try "broken".write(to: bad, atomically: true, encoding: .utf8)
    guard session.importDictionary(bad.path) != IME_OK else { exit(1) }
    guard let restored = ImeSession(wubiPath: data.appendingPathComponent("wubi86-core.tsv").path,
        pinyinCharsPath: data.appendingPathComponent("pinyin-chars.tsv").path,
        pinyinWordsPath: data.appendingPathComponent("pinyin-core.tsv").path) else { exit(1) }
    restored.setMode("mixed"); _ = restored.feed(122); _ = restored.feed(122)
    guard restored.candidates(limit: 1).first?.text == "离线测试词" else { exit(1) }
    // 设置面板（ADR-070）：Schema 驱动、界面零硬编码。
    let settingsOptions = SettingsSchema.options()
    guard settingsOptions.count == 15 else {
        fputs("设置项数量应为 15，实际 \(settingsOptions.count)。\n", stderr); exit(1)
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
    // 面板（ADR-077/080）：设置/词库 两个分区。
    guard SettingsPanel.shared.sectionCount == 2 else {
        fputs("设置面板分区数应为 2，实际 \(SettingsPanel.shared.sectionCount)。\n", stderr); exit(1)
    }
    guard AboutUI.text().contains("GPL-3.0") else {
        fputs("版本信息缺失。\n", stderr); exit(1)
    }
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
    guard diagnostics.contains("Lampyris"), diagnostics.contains("系统："),
        diagnostics.contains("架构：")
    else {
        fputs("诊断信息缺少版本/系统/架构。\n", stderr); exit(1)
    }
    try? FileManager.default.removeItem(at: smokeDirectory)
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
let delegate = PreviewDelegate(session: session)
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
