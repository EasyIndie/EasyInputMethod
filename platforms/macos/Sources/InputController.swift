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
            candidateCount = count
            session.setPageSize(count)
        }
        if let mode = ImeConfig.string("mode"), session.mode != mode {
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
        session?.toggleEnglish(); refreshAfterStateChange()
    }
    @objc private func toggleWidth(_ sender: Any?) {
        session?.toggleWidth(); refreshAfterStateChange()
    }
    @objc private func togglePunctuation(_ sender: Any?) {
        session?.togglePunctuation(); refreshAfterStateChange()
    }
    @objc private func toggleVariant(_ sender: Any?) {
        session?.toggleVariant(); refreshAfterStateChange()
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
        cancelClientComposition()
        SettingsPanel.shared.show(session: session)
    }

    @objc private func showAbout() {
        AboutUI.show()
    }

    @objc private func cycleInputMode(_ sender: Any?) {
        applyInputMode(InputStateMenu.nextMode(session?.mode ?? ImeConfig.string("mode") ?? "mixed"))
    }

    // IMK supplies a command dictionary, while local AppKit supplies the item.
    // Explicit selectors need neither a sender cast nor serialized representedObject.
    @objc private func chooseMixedMode(_ sender: Any?) { applyInputMode("mixed") }
    @objc private func chooseWubiMode(_ sender: Any?) { applyInputMode("wubi") }
    @objc private func choosePinyinMode(_ sender: Any?) { applyInputMode("pinyin") }

    private func applyInputMode(_ next: String) {
        defer { refreshStateMenu() }
        if ImeConfig.string("mode") != next, !ImeConfig.setString("mode", next) { presentConfigError(); return }
        guard session?.mode != next else { return }
        cancelClientComposition()
        session?.setMode(next)
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
            clearMarked(client)
            candidateWindow?.hide()
        }
        let shortcut = session.shortcut(event, persistMode: true)
        if shortcut.consumed {
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
            showCandidates(client, session: session)
            return true
        }
        // 组合态下 , / . 翻页（对齐搜狗/微信，可配）。
        if session.isComposing, ImeConfig.bool("candidate.page_with_comma"),
            scalar == "," || scalar == "."
        {
            session.page(scalar == "," ? -1 : 1)
            showCandidates(client, session: session)
            return true
        }

        let codepoint = feedCodepoint(scalar, shift: flags.contains(.shift), session: session)
        guard let codepoint else { return false }

        switch session.feed(codepoint) {
        case .consumed:
            updateMarked(client, session.buffer)
            showCandidates(client, session: session)
            return true
        case .committed(let text):
            commit(text, to: client)
            candidateWindow?.hide()
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

    private func showCandidates(_ client: IMKTextInput, session: ImeSession) {
        let candidates = session.candidates(limit: candidateCount)
        guard !candidates.isEmpty else {
            candidateWindow?.hide()
            return
        }
        let window = candidateWindow ?? CandidateWindow()
        candidateWindow = window
        window.onSelect = { [weak self] index in
            guard let self, let client = self.activeClient, let session = self.session else { return }
            if let text = session.select(index) {
                self.commit(text, to: client)
            }
            self.candidateWindow?.hide()
        }
        window.onPage = { [weak self] delta in
            guard let self, let client = self.activeClient, let session = self.session else { return }
            session.page(delta)
            self.showCandidates(client, session: session)
        }
        window.update(
            candidates: candidates, pageIndex: session.pageIndex, pageCount: session.pageCount,
            input: session.buffer, warning: session.variantErrorMessage)
        window.show(at: caretRect(client))
    }

    /// 光标矩形（用于定位候选窗）；取不到时退回鼠标位置。
    private func caretRect(_ client: IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect == .zero {
            let mouse = NSEvent.mouseLocation
            rect = NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)
        }
        return rect
    }
}
