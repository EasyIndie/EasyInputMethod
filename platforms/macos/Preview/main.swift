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
    }
    required init?(coder: NSCoder) { return nil }

    // Receive raw keys here instead of invoking the installed system input method.
    override var inputContext: NSTextInputContext? { nil }

    override func keyDown(with event: NSEvent) {
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
        } else if scalar == "\r" || scalar == "\n" {
            if session.isComposing {
                if let selected = session.select(0) { committed += selected }
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

    func refresh() {
        let content = NSMutableAttributedString(string: committed, attributes: [.font: NSFont.systemFont(ofSize: 24)])
        content.append(NSAttributedString(string: session.buffer, attributes: [
            .font: NSFont.systemFont(ofSize: 24), .underlineStyle: NSUnderlineStyle.single.rawValue,
            .foregroundColor: NSColor.controlAccentColor,
        ]))
        textStorage?.setAttributedString(content)
        setSelectedRange(NSRange(location: content.length, length: 0))
        let values = session.candidates(limit: ImeConfig.int("candidate.count") ?? 9)
        status?("词库：\(session.dictionaryError == IME_OK ? "正常" : "读写失败")   页：\(session.pageIndex + 1)/\(session.pageCount)   组合：\(session.buffer.isEmpty ? "（空）" : session.buffer)   候选：\(values.map(\.text).joined(separator: " · "))")
        if session.isComposing, !values.isEmpty, window != nil {
            candidates.update(candidates: values.map(\.text))
            let caret = firstRect(forCharacterRange: NSRange(location: content.length, length: 0), actualRange: nil)
            candidates.show(at: caret)
        } else { candidates.hide() }
    }

    func cancelComposition() { session.focusOut(); refresh() }
    func clear() { session.reset(); committed = ""; refresh() }
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
        let hint = NSTextField(wrappingLabelWithString: "在下方末尾输入：wq → 你，nihao → 你好。空格/数字/回车选字，退格删码，Esc 取消。\n用于引擎、FFI 和候选窗调试；系统 IMK 集成仍需实机验收。")
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
        let controls = NSStackView(views: [NSTextField(labelWithString: "会话模式"), mode, clear, add, importButton, exportButton, lookup])
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
let smoke = CommandLine.arguments.contains("--smoke-test")
let smokeDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("yinghuo-preview-\(UUID().uuidString)")
if smoke {
    try FileManager.default.createDirectory(at: smokeDirectory, withIntermediateDirectories: true)
    ime_config_init(smokeDirectory.appendingPathComponent("config.toml").path)
} else { ime_config_init(ImePaths.configFile()) }
let app = NSApplication.shared
if CommandLine.arguments.contains("--smoke-test") {
    session.setMode("mixed")
    let view = PreviewInput(session: session)
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
    keys("wq"); check("wq")
    guard session.pageCount > 1 else { fputs("缺少分页候选。\n", stderr); exit(1) }
    let firstPage = session.candidates(limit: 9).map(\.text)
    keys("=")
    guard session.pageIndex == 1, session.candidates(limit: 9).map(\.text) != firstPage else { exit(1) }
    keys("-")
    guard session.pageIndex == 0 else { exit(1) }
    guard session.candidates(limit: 1).first?.text == "你" else { exit(1) }
    keys(" nihao "); check("你你好")
    keys("wq\u{7f}"); check("你你好w")
    keys("\u{1b}"); check("你你好")
    keys("wq2"); check("你你好像")
    keys("wq\r"); check("你你好像你")
    view.clear(); check("")
    session.setMode("pinyin"); keys("nihao "); check("你好")
    view.clear(); keys("\".\""); check("“。”")
    session.focusOut(); view.clear(); keys("\""); check("“")
    keys(" ", flags: [.control, .shift]); view.clear(); keys("nihao"); check("nihao")
    keys(" ", flags: [.shift]); view.clear(); keys("A1"); check("Ａ１")
    keys(" ", flags: [.shift]); keys(" ", flags: [.control, .shift])
    keys("m", flags: [.control, .shift])
    guard session.mode == "mixed" else { exit(1) }
    guard ImeConfig.setString("appearance.theme", "dark") else { exit(1) }
    guard ImeConfig.string("appearance.theme") == "dark" else { exit(1) }
    let external = smokeDirectory.appendingPathComponent("config.toml")
    try "mode = \"wubi\"\n[candidate]\ncount = 3\n".write(to: external, atomically: true, encoding: .utf8)
    let deadline = Date().addingTimeInterval(2)
    while ImeConfig.int("candidate.count") != 3, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    guard ImeConfig.int("candidate.count") == 3 else { fputs("配置外部编辑未生效。\n", stderr); exit(1) }
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
    try? FileManager.default.removeItem(at: smokeDirectory)
    print("✅ 预览冒烟通过：文本渲染、候选、五笔/拼音、数字/回车选字、退格/Esc、清空。")
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
