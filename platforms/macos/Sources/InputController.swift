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
    private var lastAlertedConfigError: String?
    private var dataLoadError: String?
    private var lastAlertedDataError: String?

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
        session?.prepare()
        if candidateWindow == nil { candidateWindow = CandidateWindow() }
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in
            self?.configChanged(key)
        }
        presentConfigError()
        presentDataError()
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
                    failure = "码表损坏或无法解析：\(wubi)"
                } else if charsPath == nil {
                    failure = "缺少拼音字表，混输的拼音兜底不可用：\(chars)"
                }
            } else {
                failure = "缺少码表：\(wubi)"
            }
            let variant = resources.appendingPathComponent("variant-s2t.tsv").path
            if let s = session, fm.fileExists(atPath: variant) {
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
        if let count = ImeConfig.int("candidate.count"), (3...9).contains(count) {
            candidateCount = count
            session.setPageSize(count)
        }
        if let mode = ImeConfig.string("mode"), session.mode != mode {
            session.setMode(mode)
            if let client = activeClient { clearMarked(client) }
            candidateWindow?.hide()
        }
        candidateWindow?.refreshAppearance()
        if session.isComposing, let client = activeClient {
            updateMarked(client, session.buffer)
            showCandidates(client, session: session)
        }
    }

    /// 配置错误在宿主中可见；同一错误只提示一次，修复后自动复位（ADR-059）。
    private func presentConfigError() {
        guard let message = ImeConfig.errorMessage() else {
            lastAlertedConfigError = nil
            return
        }
        guard message != lastAlertedConfigError else { return }
        lastAlertedConfigError = message
        NSLog("萤火虫：\(message)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "配置文件有误，已沿用上一份有效设置"
            alert.informativeText = message
            alert.runModal()
        }
    }

    /// 数据文件异常在宿主中可见；同一错误只提示一次（ADR-063）。
    private func presentDataError() {
        guard let message = dataLoadError else {
            lastAlertedDataError = nil
            return
        }
        guard message != lastAlertedDataError else { return }
        lastAlertedDataError = message
        NSLog("萤火虫：\(message)")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "数据文件异常"
            alert.informativeText = message + "\n\n请重新安装完整包；排查步骤见文档「故障恢复」。"
            alert.runModal()
        }
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        // 输入状态（一级菜单 + 当前快捷键，ADR-076）。
        menu.addItem(
            stateItem(
                "输入模式：\(menuModeName())", action: #selector(cycleMode(_:)),
                hotkeyKey: "hotkey.toggle_mode"))
        menu.addItem(
            stateItem(
                "中/英：\(languageState())", action: #selector(toggleEnglish(_:)),
                hotkeyKey: "hotkey.toggle_english"))
        menu.addItem(
            stateItem(
                "全/半角：\(widthState())", action: #selector(toggleWidth(_:)),
                hotkeyKey: "hotkey.toggle_width"))
        menu.addItem(
            stateItem(
                "中/英标点：\(punctuationState())", action: #selector(togglePunctuation(_:)),
                hotkeyKey: "hotkey.toggle_punctuation"))
        menu.addItem(
            stateItem(
                "简/繁：\(variantState())", action: #selector(toggleVariant(_:)),
                hotkeyKey: "hotkey.toggle_variant"))
        menu.addItem(NSMenuItem.separator())
        // 词库/反查/帮助/反馈/关于统一收进设置面板（ADR-075），菜单保持精简。
        let settings = NSMenuItem(
            title: "偏好设置…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        // 异常状态（仅在出错时出现）
        var alerts: [String] = []
        if let session, session.dictionaryError != IME_OK {
            alerts.append("用户词库读写失败，请检查权限或文件格式")
        }
        if let message = ImeConfig.errorMessage() {
            alerts.append("配置错误：\(message)")
        }
        if let message = dataLoadError {
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
        return menu
    }

    /// 构造「输入状态」菜单项：标题含当前值，右侧显示当前快捷键。
    private func stateItem(_ title: String, action: Selector, hotkeyKey: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        let binding = ImeConfig.string(hotkeyKey)
        if !item.applyConfiguredHotkey(binding),
            let symbol = NSMenuItem.singleModifierSymbol(binding)
        {
            item.title = "\(title)  \(symbol)"
        }
        return item
    }

    private func languageState() -> String { (session?.isEnglish ?? false) ? "英" : "中" }
    private func widthState() -> String { (session?.isFullWidth ?? false) ? "全角" : "半角" }
    private func punctuationState() -> String {
        (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese" ? "中文" : "英文"
    }
    private func variantState() -> String {
        (ImeConfig.string("input.chinese_variant") ?? "simplified") == "traditional" ? "繁体" : "简体"
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
        guard let session else { return }
        guard let textClient = activeClient ?? (client() as? IMKTextInput) else {
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
        clearMarked(client() as? IMKTextInput)
        session?.focusOut()
        candidateWindow?.hide()
    }

    /// 模式显示名（混输/五笔/拼），用于候选窗状态徽标。
    private func modeName() -> String {
        let raw = session?.mode ?? ImeConfig.string("mode") ?? "mixed"
        return ["mixed": "混输", "wubi": "五笔", "pinyin": "拼"][raw] ?? "混输"
    }

    /// 菜单用的完整模式名（混输/五笔/拼音）。
    private func menuModeName() -> String {
        let raw = session?.mode ?? ImeConfig.string("mode") ?? "mixed"
        return ["mixed": "混输", "wubi": "五笔", "pinyin": "拼音"][raw] ?? "混输"
    }

    /// 候选窗内的紧凑状态徽标：模式（+ 全）。
    private func statusBadge() -> String {
        (session?.isFullWidth ?? false) ? "\(modeName())·全" : modeName()
    }

    /// 打开非模态设置面板（ADR-070/075）：面板承载设置/词库/帮助/反馈/关于。
    @objc private func showSettings() {
        cancelClientComposition()
        SettingsPanel.shared.show(session: session)
    }

    @objc private func cycleMode(_ sender: Any?) {
        let order = ["mixed", "wubi", "pinyin"]
        let current = ImeConfig.string("mode") ?? "mixed"
        let next = order[((order.firstIndex(of: current) ?? -1) + 1) % order.count]
        guard ImeConfig.setString("mode", next) else {
            let alert = NSAlert()
            alert.messageText = "无法保存输入模式"
            alert.informativeText = "请检查配置文件权限。当前输入模式保持不变。"
            alert.runModal()
            return
        }
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
            if let session, session.shiftTransition(isDown: event.modifierFlags.contains(.shift)) {
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
        if session.shortcut(event, persistMode: true) {
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
        if flags.contains(.control) {
            // 诊断（临时）：记录到达宿主但未匹配快捷方式的 Ctrl 组合。
            // 排查命令：log show --last 5m --predicate 'eventMessage CONTAINS "萤火虫"'
            NSLog("萤火虫：未匹配 Ctrl 组合 keyCode=\(event.keyCode) flags=\(flags.rawValue) chars=\(event.charactersIgnoringModifiers ?? "nil")")
        }
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            return false
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
        window.update(
            candidates: candidates, pageIndex: session.pageIndex, pageCount: session.pageCount,
            status: statusBadge())
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

private extension NSMenuItem {
    /// 按 `config.toml` 的快捷键写法（如 `ctrl+shift+m` / `shift+space`）显示并绑定菜单快捷键。
    ///
    /// 成功返回 `true`；`none`/空/无法表示为菜单快捷键（如单 `shift`）返回 `false`。
    @discardableResult
    func applyConfiguredHotkey(_ setting: String?) -> Bool {
        guard let setting, !setting.isEmpty, setting.lowercased() != "none" else { return false }
        let parts = setting.lowercased().split(separator: "+").map(String.init)
        guard let key = parts.last else { return false }
        var mask: NSEvent.ModifierFlags = []
        for part in parts.dropLast() {
            switch part {
            case "ctrl", "control": mask.insert(.control)
            case "shift": mask.insert(.shift)
            case "alt", "option": mask.insert(.option)
            case "cmd", "command": mask.insert(.command)
            default: return false
            }
        }
        let equivalent: String
        switch key {
        case "space": equivalent = " "
        default:
            guard key.count == 1 else { return false }
            equivalent = key
        }
        keyEquivalent = equivalent
        keyEquivalentModifierMask = mask
        return true
    }

    /// 单修饰键绑定（如 `shift`）不能做成菜单快捷键，返回其符号用于标题后缀。
    static func singleModifierSymbol(_ setting: String?) -> String? {
        switch setting?.lowercased() {
        case "shift": return "⇧"
        case "ctrl", "control": return "⌃"
        case "alt", "option": return "⌥"
        case "cmd", "command": return "⌘"
        default: return nil
        }
    }
}
