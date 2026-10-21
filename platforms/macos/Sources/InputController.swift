// 萤火虫输入法控制器：把 IMK 事件转成 `ime-ffi` 调用，再驱动预编辑与候选窗。
//
// 事件路线：handle(_:client:) → ImeSession.feed → （更新预编辑 / 上屏 / 显示候选）。
// 引擎逻辑全在 Rust；本文件只做「事件 <> 引擎 <> 文本客户端」的桥接。

import Cocoa
import InputMethodKit
import ime

@objc(LampyrisInputController)
final class LampyrisInputController: IMKInputController {
    private var session: ImeSession?
    private var candidateWindow: CandidateWindow?
    private var candidateSelection = CandidateSelectionState()
    private var candidateCount = 7
    private weak var activeClient: (any IMKTextInput)?
    private var workspaceObserver: NSObjectProtocol?
    private var dataLoadError: String?

    // MARK: - 生命周期

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        activeClient = (sender as? IMKTextInput) ?? client()
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didDeactivateApplicationNotification,
                object: nil, queue: .main
            ) { [weak self] notification in
                guard let self, let activeClient = self.activeClient,
                      let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      application.bundleIdentifier == activeClient.bundleIdentifier() else { return }
                self.finishComposition(activeClient)
            }
        }
        if session == nil {
            session = makeSession()
        }
        if candidateWindow == nil { candidateWindow = CandidateWindow() }
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in
            self?.configChanged(key)
        }
        // The observer is removed while inactive. Reapply mode as well as options
        // when a previously created client session becomes active again.
        configChanged("mode")
    }

    override func deactivateServer(_ sender: Any!) {
        finishComposition(activeClient ?? (sender as? IMKTextInput) ?? client())
        ConfigWatcher.shared.clear(owner: self)
        activeClient = nil
        super.deactivateServer(sender)
    }

    deinit {
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    override func commitComposition(_ sender: Any!) {
        finishComposition((sender as? IMKTextInput) ?? activeClient ?? client())
    }

    override func hidePalettes() {
        candidateWindow?.hide()
        super.hidePalettes()
    }

    private func finishComposition(_ textClient: (any IMKTextInput)?) {
        candidateWindow?.hide()
        candidateSelection.reset()
        session?.focusOut()
        clearMarked(textClient)
    }

    /// 装配会话：优先真实数据文件，失败回退内置样本；再套用配置（ADR-063）。
    private func makeSession() -> ImeSession? {
        var session: ImeSession?
        var failure: String?
        if let resources = Bundle.main.resourceURL {
            let wubi = resources.appendingPathComponent("wubi86-core.tsv").path
            let chars = resources.appendingPathComponent("pinyin-chars.tsv").path
            let words = resources.appendingPathComponent("pinyin-core.tsv").path
            let fm = FileManager.default
            if fm.fileExists(atPath: wubi) {
                let charsPath = fm.fileExists(atPath: chars) ? chars : nil
                let wordsPath = (charsPath != nil && fm.fileExists(atPath: words)) ? words : nil
                session = ImeSession(
                    wubiPath: wubi, pinyinCharsPath: charsPath, pinyinWordsPath: wordsPath)
                if session == nil {
                    failure = "码表或拼音数据损坏、为空或无法读取，请重新安装完整包：\(resources.path)"
                } else if charsPath == nil {
                    failure = "缺少拼音字表，混输的拼音兜底不可用：\(chars)"
                } else if wordsPath == nil {
                    failure = "缺少拼音词表，拼音词组及简拼不可用：\(words)"
                }
            } else {
                failure = "缺少码表：\(wubi)"
            }
            let variant = resources.appendingPathComponent("variant-s2t.tsv").path
            if let s = session {
                _ = s.setVariantData(variant)
            }
        } else {
            failure = "找不到应用资源目录，无法加载数据文件"
        }
        dataLoadError = failure
        if session == nil {
            NSLog("萤火虫：\(failure ?? "数据加载失败")，回退内置样本引擎")
            session = ImeSession.sample()
        }
        if let mode = ImeConfig.string("mode") {
            session?.setMode(mode)
        }
        if let count = ImeConfig.int("candidate.count"), (3...9).contains(count) {
            candidateCount = count
        }
        return session
    }

    // MARK: - 输入菜单（模式切换；正式交互属 P1-M4）

    /// 配置在无按键时变更（外部编辑或菜单写入）后，即时应用到会话与候选窗（ADR-058）。
    func configChanged(_ key: String) {
        presentConfigError()
        guard let session else { return }
        session.prepare()
        presentDataError()
        if let count = ImeConfig.int("candidate.count"), (3...9).contains(count) {
            if candidateCount != count { candidateSelection.reset() }
            candidateCount = count
            session.setPageSize(count)
        }
        if let mode = ImeConfig.string("mode"), session.mode != mode {
            candidateSelection.reset()
            session.setMode(mode)
            if let client = activeClient { clearMarked(client) }
            candidateWindow?.hide()
        }
        refreshStateMenu()
        candidateWindow?.refreshAppearance()
        if session.isComposing, let client = activeClient {
            updateMarked(client, session.buffer)
            showCandidates(client, session: session)
        }
    }

    /// 配置错误在宿主中可见；同一错误只提示一次，修复后自动复位（ADR-059）。
    private func presentConfigError() {
        ProcessErrorPresenter.shared.update(
            channel: "configuration", title: "设置未生效，已沿用上一份有效设置",
            current: { ImeConfig.errorMessage() })
    }

    private func presentDataError() {
        ProcessErrorPresenter.shared.update(channel: "resources", title: "数据文件异常") { [weak self] in
            guard let self, let message = self.dataLoadError ?? self.session?.variantErrorMessage else { return nil }
            return message + "\n\n请重新安装完整包；排查步骤见文档「故障恢复」。"
        }
    }

    override func menu() -> NSMenu! {
        let menu = InputStateMenu.make(state: inputMenuState(), target: self)
        stateMenu = menu
        refreshStateMenu()
        menu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(
            title: "设置", action: #selector(showSettings), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(
            title: "关于", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        // 异常状态（仅在出错时出现）
        var alerts: [String] = []
        if let session, session.dictionaryError != IME_OK {
            alerts.append("用户词库读写失败，请检查权限或文件格式")
        }
        if let message = ImeConfig.errorMessage() {
            alerts.append("配置错误：\(message)")
        }
        if let message = dataLoadError ?? session?.variantErrorMessage {
            alerts.append("数据文件错误：\(message)")
        }
        if !alerts.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for title in alerts {
                let status = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                status.isEnabled = false
                menu.addItem(status)
            }
        }
        refreshStateMenu()
        return menu
    }

    private var stateMenu: NSMenu?

    private func inputMenuState() -> InputMenuState {
        InputMenuState(mode: session?.mode ?? ImeConfig.string("mode") ?? "mixed",
            language: languageState(), width: widthState(), variant: variantState(),
            punctuation: punctuationState(), enabled: session != nil)
    }

    private func refreshStateMenu() {
        guard let menu = stateMenu else { return }
        for (item, key) in zip(menu.items.prefix(5), InputStateMenu.shortcuts) {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            let binding = ImeConfig.hotkey(key)
            if !item.applyConfiguredHotkey(binding), let symbol = NSMenuItem.singleModifierSymbol(binding) {
                item.keyEquivalent = symbol
                item.keyEquivalentModifierMask = []
            }
        }
        if menu.items.count >= 8 {
            for (item, key) in [(menu.items[6], "hotkey.open_settings"), (menu.items[7], "hotkey.open_about")] {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
                _ = item.applyConfiguredHotkey(ImeConfig.hotkey(key))
            }
        }
        InputStateMenu.refresh(menu, state: inputMenuState())
    }

    private func languageState() -> String { (session?.isEnglish ?? false) ? "英文" : "中文" }
    private func widthState() -> String { (session?.isFullWidth ?? false) ? "全角" : "半角" }
    private func punctuationState() -> String {
        (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese" ? "中文标点" : "英文标点"
    }
    private func variantState() -> String {
        if let session, session.variantError != IME_OK { return "简体（繁体数据异常）" }
        return session?.isTraditional == true ? "繁体" : "简体"
    }

    @objc private func toggleEnglish(_ sender: Any?) {
        session?.toggleEnglish()
        showStateFeedback(StateFeedback.language(session?.isEnglish ?? false))
        refreshAfterStateChange()
    }
    @objc private func toggleWidth(_ sender: Any?) {
        session?.toggleWidth()
        showStateFeedback(StateFeedback.width(session?.isFullWidth ?? false))
        refreshAfterStateChange()
    }
    @objc private func togglePunctuation(_ sender: Any?) {
        session?.togglePunctuation()
        showStateFeedback(StateFeedback.punctuation(
            (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese"))
        refreshAfterStateChange()
    }
    @objc private func toggleVariant(_ sender: Any?) {
        session?.toggleVariant()
        showStateFeedback(StateFeedback.variant(session?.isTraditional ?? false))
        refreshAfterStateChange()
    }

    /// 候选窗可见时状态直接画在头部芯片里，不再弹 HUD（ADR-211）。
    private func showStateFeedback(_ message: String) {
        // 只有会话仍在组合、候选窗会保留时才内联；宽度/模式/中英会 cancel 组合，
        // 这类切换必须走 HUD，否则候选窗随即关闭、用户什么都看不到。
        if let window = candidateWindow, window.isVisible, session?.isComposing == true {
            window.updateStatus(candidateStatus())
            window.refreshLayout()
            return
        }
        StateHUDController.shared.show(message, caret: hudCaretRect())
    }

    /// HUD 用光标矩形：无客户端/取不到时返回 nil（不显示，不退鼠标）。
    /// `attributes` 优先（文本视图线高矩形，位置准），`firstRect` 兜底（终端类客户端只实现它）。
    /// 空文档保留提示（插入点在文档开头）；Finder 桌面/图标视图没有文本时不算有效光标（ADR-214）。
    private func hudCaretRect() -> NSRect? {
        // 只接受“属于前台应用”的客户端：切换应用后 IMK 可能仍持有上一个应用的 client，
        // 用它会把提示放到上一个应用的插入点（报告 095 实测 Finder 桌面因此误显示）。
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        func belongsToFrontmost(_ candidate: (any IMKTextInput)?) -> (any IMKTextInput)? {
            guard let candidate else { return nil }
            let bundle = candidate.bundleIdentifier() ?? ""
            guard !bundle.isEmpty, let frontmost, !frontmost.isEmpty else { return candidate }
            return bundle == frontmost ? candidate : nil
        }
        guard let client = belongsToFrontmost(client()) ?? belongsToFrontmost(activeClient) else {
            return nil
        }
        let length = max(0, client.length())
        let selection = client.selectedRange()
        let bundle = client.bundleIdentifier() ?? ""
        let windowLevel = client.windowLevel()
        let diag = Self.hudDiagEnabled
        let startIndex = Self.caretLookupIndex(
            selectionLocation: selection.location, length: length)
        guard let rect = StateHUDCaretResolver.resolve(
            startIndex: startIndex,
            hasText: length > 0,
            allowsEmptyCaret: true,
            lineRect: { index in
                var rect = NSRect.zero
                _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
                if diag { Self.hudDiag("line\(index)=\(NSStringFromRect(rect))") }
                return rect
            },
            firstRect: { index in
                var actual = NSRange()
                let rect = client.firstRect(
                    forCharacterRange: NSRange(location: index, length: 0),
                    actualRange: &actual)
                if diag { Self.hudDiag("first\(index)=\(NSStringFromRect(rect))") }
                return rect
            })
        else { return nil }
        if diag {
            Self.hudDiag("pick bundle=\(bundle) len=\(length) sel=\(selection.location) "
                + "level=\(windowLevel) rect=\(NSStringFromRect(rect))")
        }
        guard StateHUDLayout.isOnScreen(caret: rect, screens: NSScreen.screens.map(\.frame)) else {
            return nil
        }
        // 桌面/图标视图会给出一个“伪光标”，它只落在桌面层窗口里（层号极大且为负），
        // 真输入框（含 Finder 搜索框、空文档）都在应用的普通窗口里（层号 >= 0）。报告 096。
        guard Self.caretInsideAppWindow(rect, bundle: bundle) else {
            if diag { Self.hudDiag("drop: caret not inside app window") }
            return nil
        }
        return rect
    }

    /// 光标中心是否落在前台应用的普通窗口（层号 >= 0）里；取不到信息时放行，避免误杀。
    private static func caretInsideAppWindow(_ caret: NSRect, bundle: String) -> Bool {
        guard !bundle.isEmpty,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
              let primaryTop = Self.primaryScreenTop else { return true }
        let point = StateHUDLayout.cgPoint(NSPoint(x: caret.midX, y: caret.midY), primaryTop: primaryTop)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return true }
        var sawWindow = false
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary)
            else { continue }
            sawWindow = true
            if rect.contains(point) { return true }
        }
        // 看不到该应用的常规窗口时放行（避免误杀），只有“看得到窗口但光标不在其中”才判定为桌面伪光标。
        return !sawWindow
    }

    /// Cocoa→CG 的主屏高度：取原点在 (0,0) 的那块屏（菜单栏所在屏），退化为 `NSScreen.main`。
    private static var primaryScreenTop: CGFloat? {
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        return primary?.frame.maxY
    }

    /// 诊断开关（默认关闭）：`launchctl setenv LAMPYRIS_HUD_DIAG 1` 后重启宿主，
    /// 光标矩形解析过程写入 `$TMPDIR/lampyris-hud-diag.log`，用于真机定位 HUD 偏移。
    static var hudDiagEnabled: Bool {
        ProcessInfo.processInfo.environment["LAMPYRIS_HUD_DIAG"] != nil
    }

    static func hudDiag(_ message: String) {
        let path = NSTemporaryDirectory() + "lampyris-hud-diag.log"
        let line = "[hud] " + message + "\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    private func candidateStatus() -> CandidateStatus {
        CandidateStatus(
            mode: session?.mode ?? ImeConfig.string("mode") ?? "mixed",
            english: session?.isEnglish ?? false,
            fullWidth: session?.isFullWidth ?? false,
            traditional: session?.isTraditional ?? false,
            chinesePunctuation: (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese")
    }

    /// 状态切换后刷新预编辑/候选（与快捷键路径一致）。
    private func refreshAfterStateChange() {
        refreshStateMenu()
        guard let session else { return }
        guard let textClient = activeClient ?? client() else {
            candidateWindow?.hide()
            return
        }
        if session.isComposing {
            updateMarked(textClient, session.buffer)
            showCandidates(textClient, session: session)
        } else {
            clearMarked(textClient)
            candidateWindow?.hide()
        }
    }

    private func cancelClientComposition() {
        clearMarked(client())
        session?.focusOut()
        candidateWindow?.hide()
    }

    /// 打开非模态设置面板（ADR-070/075）：面板承载设置/词库/帮助/反馈/关于。
    @objc private func showSettings() {
        let marks = PerfTrace.shared.begin()
        cancelClientComposition()
        SettingsPanel.shared.show(session: session)
        PerfTrace.shared.finishPanel(marks, panel: "settings")
    }

    @objc private func showAbout() {
        let marks = PerfTrace.shared.begin()
        AboutUI.show()
        PerfTrace.shared.finishPanel(marks, panel: "about")
    }

    @objc private func performInputMenuCommand(_ sender: Any?) {
        guard let command = InputStateMenu.command(from: sender) else { return }
        switch command {
        case .cycleMode:
            applyInputMode(InputStateMenu.nextMode(session?.mode ?? ImeConfig.string("mode") ?? "mixed"))
        case .toggleEnglish: toggleEnglish(sender)
        case .toggleWidth: toggleWidth(sender)
        case .toggleVariant: toggleVariant(sender)
        case .togglePunctuation: togglePunctuation(sender)
        }
    }

    private func applyInputMode(_ next: String) {
        defer { refreshStateMenu() }
        if ImeConfig.string("mode") != next, !ImeConfig.setString("mode", next) { presentConfigError(); return }
        guard session?.mode != next else { return }
        cancelClientComposition()
        session?.setMode(next)
        showStateFeedback(StateFeedback.mode(next))
    }

    // MARK: - 按键处理

    /// 让 IMK 额外转发修饰键变化（单独 Shift 必需）与鼠标按下（顶替默认的点击外部提交）。
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(
            NSEvent.EventTypeMask.keyDown.rawValue
                | NSEvent.EventTypeMask.flagsChanged.rawValue
                | NSEvent.EventTypeMask.leftMouseDown.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        // 单独 Shift 切换中英（flagsChanged，对齐搜狗/微信）。
        if event.type == .flagsChanged {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            session?.noteModifierChange(event)
            let other =
                flags.contains(.control) || flags.contains(.option) || flags.contains(.command)
            if let session,
                session.shiftTransition(isDown: flags.contains(.shift), otherModifier: other)
            {
                if let client = activeClient ?? (sender as? IMKTextInput) { clearMarked(client) }
                candidateWindow?.hide()
            }
            return false
        }
        // 鼠标按下：保留“点击组合外则结束当前组合”（IMK 默认行为）；事件继续透传客户端。
        if event.type == .leftMouseDown {
            if let session, session.isComposing {
                finishComposition(activeClient ?? (sender as? IMKTextInput))
            }
            return false
        }
        guard event.type == .keyDown, let session, let client = sender as? IMKTextInput else {
            return false
        }
        activeClient = client
        session.markKeyWhileShift()
        if let mode = ImeConfig.string("mode"), session.mode != mode {
            session.setMode(mode)
            candidateSelection.reset()
            clearMarked(client)
            candidateWindow?.hide()
        }
        if session.matches("hotkey.open_settings", event) {
            showSettings()
            return true
        }
        if session.matches("hotkey.open_about", event) {
            showAbout()
            return true
        }
        let modeBeforeShortcut = session.mode
        let learningBeforeShortcut = ImeConfig.bool("candidate.show_wubi_learning")
        let shortcut = session.shortcut(event, persistMode: true)
        if shortcut.consumed {
            if session.mode != modeBeforeShortcut {
                showStateFeedback(StateFeedback.mode(session.mode))
            } else if ImeConfig.bool("candidate.show_wubi_learning") != learningBeforeShortcut {
                showStateFeedback(StateFeedback.learning(
                    ImeConfig.bool("candidate.show_wubi_learning")))
            }
            if shortcut == .failed { presentConfigError() }
            if session.isComposing {
                updateMarked(client, session.buffer)
                showCandidates(client, session: session)
            } else {
                clearMarked(client)
                candidateWindow?.hide()
            }
            return true
        }
        // 放行带命令/控制/选项修饰键的按键（保住 Cmd+Z 等系统快捷键）
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
        }
        if session.isComposing, let delta = candidateWindow?.navigationDelta(for: event) {
            let count = session.candidates(limit: candidateCount).count
            _ = candidateSelection.move(delta, count: count)
            updateMarked(client, session.buffer)
            showCandidates(client, session: session)
            return true
        }
        // Do not let the client edit marked text behind the engine's buffer.
        if session.consumesCompositionNavigation(event) {
            updateMarked(client, session.buffer)
            showCandidates(client, session: session)
            return true
        }
        guard let chars = event.charactersIgnoringModifiers, let scalar = chars.unicodeScalars.first
        else { return false }

        if let count = ImeConfig.int("candidate.count") {
            candidateCount = count
            session.setPageSize(count)
        }
        if session.isComposing, scalar.value == 0xF72C || scalar.value == 0xF72D {
            session.page(scalar.value == 0xF72C ? -1 : 1)
            candidateSelection.reset()
            showCandidates(client, session: session)
            return true
        }
        // 组合态下 , / . 翻页（对齐搜狗/微信，可配）。
        if session.isComposing, ImeConfig.bool("candidate.page_with_comma"),
            scalar == "," || scalar == "."
        {
            session.page(scalar == "," ? -1 : 1)
            candidateSelection.reset()
            showCandidates(client, session: session)
            return true
        }

        if session.isComposing, event.keyCode == 49, candidateSelection.index > 0,
            let text = session.select(candidateSelection.index)
        {
            commit(text, to: client)
            candidateSelection.reset()
            candidateWindow?.hide()
            return true
        }

        let codepoint = feedCodepoint(scalar, shift: flags.contains(.shift), session: session)
        guard let codepoint else { return false }

        candidateSelection.reset()
        let trace = PerfTrace.shared.begin()
        let outcome = session.feed(codepoint)
        let engineStamp = PerfTrace.shared.stamp()
        switch outcome {
        case .consumed:
            updateMarked(client, session.buffer)
            let shown = showCandidates(client, session: session)
            PerfTrace.shared.finish(trace, engine: engineStamp, candidates: shown, committed: false)
            return true
        case .committed(let text):
            commit(text, to: client)
            candidateWindow?.hide()
            PerfTrace.shared.finish(trace, engine: engineStamp, candidates: 1, committed: true)
            return true
        case .passThrough:
            return false
        case .failure:
            return false
        }
    }

    /// 计算喂给引擎的码点：字母统一小写（五笔码）；Shift+字母在非组合态直通英文。
    private func feedCodepoint(_ scalar: Unicode.Scalar, shift: Bool, session: ImeSession)
        -> UInt32?
    {
        if session.isEnglish { return scalar.value }
        if scalar.isASCII, scalar.properties.isAlphabetic {
            if shift, !session.isComposing {
                return nil
            }
            let lower = String(scalar).lowercased()
            return lower.unicodeScalars.first?.value
        }
        return scalar.value
    }

    // MARK: - 预编辑 / 上屏 / 候选窗

    private func updateMarked(_ client: IMKTextInput, _ buffer: String) {
        let attributed = NSAttributedString(
            string: buffer,
            attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: buffer.utf16.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    private func clearMarked(_ client: IMKTextInput?) {
        guard let client else { return }
        updateMarked(client, "")
    }

    private func commit(_ text: String, to client: IMKTextInput) {
        clearMarked(client)
        guard !text.isEmpty else { return }
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    @discardableResult
    private func showCandidates(_ client: IMKTextInput, session: ImeSession) -> Int {
        let candidates = session.candidates(limit: candidateCount)
        guard !candidates.isEmpty else {
            candidateWindow?.hide()
            return 0
        }
        let window = candidateWindow ?? CandidateWindow()
        candidateWindow = window
        window.onSelect = { [weak self] index in
            guard let self, let client = self.activeClient, let session = self.session else { return }
            if let text = session.select(index) {
                self.commit(text, to: client)
            }
            self.candidateSelection.reset()
            self.candidateWindow?.hide()
        }
        window.onPage = { [weak self] delta in
            guard let self, let client = self.activeClient, let session = self.session else { return }
            session.page(delta)
            self.candidateSelection.reset()
            self.showCandidates(client, session: session)
        }
        window.updateStatus(candidateStatus())
        window.update(
            candidates: candidates, pageIndex: session.pageIndex, pageCount: session.pageCount,
            selectedIndex: candidateSelection.index,
            input: session.buffer, showsNavigationHint: true,
            warning: session.variantErrorMessage)
        window.show(at: caretRect(client))
        return candidates.count
    }

    /// 光标常在文本末尾（location == length），查询 length 会得到空矩形；
    /// 退一格取最后一个字符的位置，HUD/候选窗才会贴着真实光标。
    static func caretLookupIndex(selectionLocation: Int, length: Int) -> Int {
        guard length > 0 else { return 0 }
        let location = selectionLocation == NSNotFound ? 0 : selectionLocation
        return min(max(0, location), length - 1)
    }

    /// 光标矩形（候选窗/HUD 定位）；优先当前插入点，取不到时退回鼠标位置。
    private func caretRect(_ client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        let selection = client.selectedRange()
        let index = Self.caretLookupIndex(selectionLocation: selection.location,
            length: client.length())
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        if rect == .zero {
            let mouse = NSEvent.mouseLocation
            rect = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        }
        return rect
    }
}
