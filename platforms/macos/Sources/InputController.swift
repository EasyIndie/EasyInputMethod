// 萤火虫输入法控制器：把 IMK 事件转成 `ime-ffi` 调用，再驱动预编辑与候选窗。
//
// 事件路线：handle(_:client:) → ImeSession.feed → （更新预编辑 / 上屏 / 显示候选）。
// 引擎逻辑全在 Rust；本文件只做「事件 <> 引擎 <> 文本客户端」的桥接。

import Cocoa
import InputMethodKit
import ime

@objc(YinghuoInputController)
final class YinghuoInputController: IMKInputController {
    private var session: ImeSession?
    private var candidateWindow: CandidateWindow?
    private var candidateCount = 7

    // MARK: - 生命周期

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        if session == nil {
            session = makeSession()
        }
        session?.prepare()
    }

    override func deactivateServer(_ sender: Any!) {
        clearMarked(sender as? IMKTextInput)
        session?.focusOut()
        candidateWindow?.hide()
        super.deactivateServer(sender)
    }

    /// 装配会话：优先真实数据文件，失败回退内置样本；再套用配置。
    private func makeSession() -> ImeSession? {
        var session: ImeSession?
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
            }
        }
        if session == nil {
            NSLog("萤火虫：未找到数据文件，回退内置样本引擎")
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

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let current = ImeConfig.string("mode") ?? "mixed"
        let item = NSMenuItem(
            title: "切换输入模式（当前：\(current)）",
            action: #selector(cycleMode(_:)),
            keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        for (title, action) in [("新增用户词条…", #selector(addWord)), ("导入用户词库…", #selector(importWords)),
            ("导出用户词库…", #selector(exportWords)), ("拼音反查…", #selector(lookupPinyin))] {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self; menu.addItem(entry)
        }
        if let session, session.dictionaryError != IME_OK {
            let status = NSMenuItem(title: "用户词库读写失败，请检查权限或文件格式", action: nil, keyEquivalent: "")
            menu.addItem(status)
        }
        return menu
    }

    private func cancelClientComposition() {
        clearMarked(client() as? IMKTextInput)
        session?.focusOut()
        candidateWindow?.hide()
    }

    @objc private func lookupPinyin() {
        guard let session else { return }
        cancelClientComposition(); LookupUI.show(session)
    }
    @objc private func addWord() {
        guard let session else { return }
        cancelClientComposition(); UserDictionaryUI.add(session)
    }
    @objc private func importWords() {
        guard let session else { return }
        cancelClientComposition(); UserDictionaryUI.importFile(session)
    }
    @objc private func exportWords() {
        guard let session else { return }
        cancelClientComposition(); UserDictionaryUI.exportFile(session)
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

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard event.type == .keyDown, let session, let client = sender as? IMKTextInput else {
            return false
        }
        if let mode = ImeConfig.string("mode"), session.mode != mode {
            session.setMode(mode)
            clearMarked(client)
            candidateWindow?.hide()
        }
        if session.shortcut(event, persistMode: true) {
            clearMarked(client); candidateWindow?.hide(); return true
        }
        // 放行带命令/控制/选项修饰键的按键（保住 Cmd+Z 等系统快捷键）
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
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
        // 回车：组合中则上屏首选候选
        if scalar == "\r" || scalar == "\n" {
            guard session.isComposing else { return false }
            if let text = session.select(0) {
                commit(text, to: client)
                candidateWindow?.hide()
            }
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
        window.update(candidates: candidates.map(\.text))
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
