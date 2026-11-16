import Cocoa

/// 宿主内文本输入（ADR-363）：IMK 不能给输入法自己的宿主进程当客户端，
/// 系统会把这些窗口退回基础键盘布局，所以宿主里的搜索框、词条文本、跟打输入框
/// 原来打不出中文，也没有候选。
///
/// 这里用**同一个 `ImeSession`** 在进程内做最小组合：组合、候选、上屏与系统输入路径
/// 共享引擎和会话 API（`feed` / `candidates` / `select` / `page`），只是不经过 IMK。
/// 只对显式 `attach` 的字段生效——只收字母/数字的输入框（编码、快捷键、候选数）保持原样，
/// 不会被本地组合抢键。
final class InHostTextInput {
    static let shared = InHostTextInput()

    private struct WeakField { weak var value: NSTextField? }

    private var fields: [WeakField] = []
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private var session: ImeSession?
    private var candidates: CandidateWindow?
    private var selection = CandidateSelectionState()
    private weak var activeEditor: NSTextView?

    private init() {}

    /// 给一个期望输入中文的文本框接上本地组合；重复调用无副作用。
    func attach(_ field: NSTextField) {
        fields.removeAll { $0.value == nil }
        guard !fields.contains(where: { $0.value === field }) else { return }
        fields.append(WeakField(value: field))
        install()
    }

    /// 是否已经装上事件监视（测试与诊断用）。
    var isInstalled: Bool { monitor != nil }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event) ? nil : event
        }
        // 窗口失焦/关闭时把组合收干净，避免 marked text 留在字段里。
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    /// 处理一个按键：`true` = 已消费，`false` = 放行给字段。
    private func handle(_ event: NSEvent) -> Bool {
        guard let field = attachedField(for: event) else {
            cancel()
            return false
        }
        guard let editor = field.currentEditor() as? NSTextView else {
            cancel()
            return false
        }
        activeEditor = editor
        if session == nil {
            session = makeSession()
            guard let session else { return false }
            syncMode(session)
        }
        guard let session else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 系统快捷键（⌘/⌃/⌥）与 Shift 开头的按键原样放行；组合中先落盘再放行。
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            cancel()
            return false
        }
        if !session.isComposing, flags.contains(.shift) { return false }

        if session.isComposing, let delta = candidates?.navigationDelta(for: event) {
            let count = session.candidates(limit: candidateCount).count
            _ = selection.move(delta, count: count)
            session.setHighlight(selection.index)
            refresh(editor, session: session)
            return true
        }
        guard let scalar = typedScalar(event) else { return false }
        // 非组合态只从字母起手：数字、标点、空格按普通文本输入放行。
        if !session.isComposing, !(scalar.isASCII && scalar.properties.isAlphabetic) { return false }

        if session.isComposing, scalar == " ", selection.index > 0,
           let text = session.select(selection.index) {
            commit(text, to: editor, session: session)
            return true
        }
        selection.reset()
        session.setHighlight(0)
        let outcome = session.feed(feedCodepoint(scalar, session: session))
        switch outcome {
        case .consumed:
            refresh(editor, session: session)
            return true
        case .committed(let text):
            commit(text, to: editor, session: session)
            return true
        case .passThrough:
            if session.isComposing {
                refresh(editor, session: session)
                return true
            }
            clearMarked(editor)
            candidates?.hide()
            return false
        case .failure:
            return false
        }
    }

    private var candidateCount: Int { max(1, ImeConfig.int("candidate.count") ?? 9) }

    private func attachedField(for event: NSEvent) -> NSTextField? {
        guard event.type == .keyDown, let window = NSApp.keyWindow else { return nil }
        guard let editor = window.firstResponder as? NSTextView, editor.isEditable else { return nil }
        return fields.compactMap(\.value).first { $0.currentEditor() === editor }
    }

    /// 资源既可能在 `Resources/`（正式包），也可能在 `Resources/data/`（调试预览的软链）。
    private func resourcePath(_ name: String) -> String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let manager = FileManager.default
        for url in [resources.appendingPathComponent(name),
                    resources.appendingPathComponent("data").appendingPathComponent(name)] {
            if manager.fileExists(atPath: url.path) { return url.path }
        }
        return nil
    }

    private func makeSession() -> ImeSession? {
        guard let wubi = resourcePath("wubi86-core.tsv") else { return ImeSession.sample() }
        return ImeSession(wubiPath: wubi,
                          pinyinCharsPath: resourcePath("pinyin-chars.tsv"),
                          pinyinWordsPath: resourcePath("pinyin-core.tsv"))
            ?? ImeSession.sample()
    }

    /// 与正式宿主一致：每次开始组合前对齐配置里的模式（切模式后不必重启面板）。
    private func syncMode(_ session: ImeSession) {
        if let mode = ImeConfig.string("mode"), session.mode != mode { session.setMode(mode) }
        if let count = ImeConfig.int("candidate.count") { session.setPageSize(count) }
    }

    private func typedScalar(_ event: NSEvent) -> Unicode.Scalar? {
        let shift = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.shift)
        let computed = event.characters(byApplyingModifiers: shift ? [.shift] : [])
        let chars = (computed?.isEmpty == false ? computed : nil) ?? event.charactersIgnoringModifiers
        return chars?.unicodeScalars.first
    }

    /// 与 `InputController.feedCodepoint` 同源：字母统一小写；英文态原样喂。
    private func feedCodepoint(_ scalar: Unicode.Scalar, session: ImeSession) -> UInt32 {
        if session.isEnglish { return scalar.value }
        if scalar.isASCII, scalar.properties.isAlphabetic {
            let lower = String(scalar).lowercased()
            return lower.unicodeScalars.first?.value ?? scalar.value
        }
        return scalar.value
    }

    private func refresh(_ editor: NSTextView, session: ImeSession) {
        let buffer = session.buffer
        if buffer.isEmpty {
            clearMarked(editor)
            candidates?.hide()
            return
        }
        editor.setMarkedText(
            NSAttributedString(string: buffer,
                               attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue]),
            selectedRange: NSRange(location: buffer.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        let window = candidates ?? CandidateWindow()
        candidates = window
        let values = session.candidates(limit: candidateCount)
        guard !values.isEmpty else {
            // 没有候选时只留预编辑串，不弹一个空面板。
            window.hide()
            return
        }
        window.update(candidates: values, pageIndex: session.pageIndex, pageCount: session.pageCount,
                      selectedIndex: selection.index, input: buffer, showsNavigationHint: true)
        window.show(at: caretRect(for: editor))
    }

    private func commit(_ text: String, to editor: NSTextView, session: ImeSession) {
        clearMarked(editor)
        candidates?.hide()
        selection.reset()
        session.setHighlight(0)
        guard !text.isEmpty else { return }
        editor.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func clearMarked(_ editor: NSTextView) {
        guard editor.hasMarkedText() else { return }
        editor.setMarkedText("", selectedRange: NSRange(location: 0, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// 插入点矩形（屏幕坐标）：候选窗按它落点。取不到时退化到字段左下角。
    private func caretRect(for editor: NSTextView) -> NSRect {
        let range = editor.selectedRange()
        let rect = editor.firstRect(forCharacterRange: NSRange(location: range.location, length: 0),
                                    actualRange: nil)
        if !rect.isNull, rect.width.isFinite, rect.height.isFinite, rect.height > 0 { return rect }
        guard let window = editor.window else { return .zero }
        let frame = window.convertToScreen(editor.convert(editor.bounds, to: nil))
        return NSRect(x: frame.minX, y: frame.minY, width: 1, height: frame.height)
    }

    /// 取消当前组合（失焦、Esc 之外的窗口切换）：清 marked text 与候选窗，不改字段内容。
    func cancel() {
        guard let session else { return }
        if let editor = activeEditor { clearMarked(editor) }
        session.reset()
        selection.reset()
        candidates?.hide()
        activeEditor = nil
    }
}
