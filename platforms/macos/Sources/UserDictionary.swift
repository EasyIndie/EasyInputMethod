import Cocoa
import UniformTypeIdentifiers
import ime

/// A labelled native form shared by real operations and offscreen verification.
final class DictionaryEntryForm: NSView {
    let scheme = NSPopUpButton()
    let code = NSTextField()
    let text = NSTextField()
    let status = NSTextField(wrappingLabelWithString: "")

    init(mode: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 210))
        scheme.addItems(withTitles: ["五笔", "拼音"])
        scheme.selectItem(at: mode == "pinyin" ? 1 : 0)
        scheme.setAccessibilityLabel("输入方案")
        code.placeholderString = "例如 wqiy 或 nihao"
        code.setAccessibilityLabel("完整编码")
        code.setAccessibilityHelp("1至64个小写英文字母，不含空格。")
        text.placeholderString = "例如 你好"
        text.setAccessibilityLabel("词条文本")
        text.setAccessibilityHelp("精确匹配的汉字或词组，最多256个UTF-8字节。")
        let labels = ["输入方案", "完整编码", "词条文本"].map { title -> NSTextField in
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 13)
            return label
        }
        let grid = NSGridView(views: [[labels[0], scheme], [labels[1], code], [labels[2], text]])
        grid.columnSpacing = 12
        grid.rowSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 260
        grid.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 12)
        status.textColor = ImeAppearance.errorText
        status.setAccessibilityLabel("词条操作结果")
        status.preferredMaxLayoutWidth = 360
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid); addSubview(status)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            status.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 12),
            status.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            status.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            status.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
        ])
        scheme.nextKeyView = code; code.nextKeyView = text
    }
    required init?(coder: NSCoder) { nil }
}

enum UserDictionaryUI {
    static func report(_ code: Int32, detail: String? = nil) {
        guard code != IME_OK else { return }
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = "用户词库操作失败"
        alert.informativeText = detail ?? "请检查词条格式、文件权限或锁文件。原有词库不会因无效导入被覆盖。（错误码：\(code)）"
        alert.runModal()
    }
    @discardableResult
    static func add(_ session: ImeSession) -> Bool { edit(session, deleting: false) }

    @discardableResult
    static func remove(_ session: ImeSession) -> Bool { edit(session, deleting: true) }

    static func entryError(_ result: Int32, code: String, text: String) -> String {
        if result == IME_ERR_NOT_FOUND { return "未找到此用户词条，请核对方案、完整编码和文本。" }
        if result == IME_ERR_INVALID_INPUT {
            if code.isEmpty || code.utf8.count > 64 || !code.utf8.allSatisfy({ $0 >= 97 && $0 <= 122 }) {
                return "编码须为1–64个小写英文字母，不含空格。"
            }
            if text.isEmpty || text.utf8.count > 256 || text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                return "文本不能为空、不能含控制字符，且不能超过256个UTF-8字节。"
            }
        }
        return "保存失败，请检查词库文件权限或锁文件；输入已保留。（错误码：\(result)）"
    }

    private static func edit(_ session: ImeSession, deleting: Bool) -> Bool {
        session.focusOut()
        let (alert, form) = makeEntryAlert(mode: session.mode, deleting: deleting)
        let scheme = form.scheme, code = form.code, text = form.text, status = form.status
        while alert.runModal() == .alertFirstButtonReturn {
            let selected = scheme.indexOfSelectedItem == 0 ? "wubi" : "pinyin"
            let result = deleting
                ? session.removeWord(scheme: selected, code: code.stringValue, text: text.stringValue)
                : session.addWord(scheme: selected, code: code.stringValue, text: text.stringValue)
            if result == IME_OK { return true }
            status.stringValue = entryError(result, code: code.stringValue, text: text.stringValue)
        }
        return false
    }
    static func makeEntryAlert(mode: String, deleting: Bool) -> (NSAlert, DictionaryEntryForm) {
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = deleting ? "删除用户词条" : "新增用户词条"
        alert.informativeText = deleting
            ? "按方案、完整编码和文本精确删除用户词条及学习记录；内置词不会删除。纠错后可重新添加。"
            : "编码使用小写英文字母；拼音输入完整拼音，不加空格。"
        alert.addButton(withTitle: deleting ? "删除此词条" : "添加")
        alert.addButton(withTitle: "取消")
        if deleting {
            alert.buttons[0].keyEquivalent = ""
            alert.buttons[1].keyEquivalent = "\r"
        }
        let form = DictionaryEntryForm(mode: mode)
        alert.accessoryView = form
        alert.window.initialFirstResponder = form.code
        return (alert, form)
    }
    @discardableResult
    static func importFile(_ session: ImeSession) -> URL? {
        session.focusOut()
        let panel = NSOpenPanel()
        ImeAppearance.applyTheme(to: panel)
        panel.title = "导入用户词库"
        panel.message = "选择本地TSV词库文件；无效导入不会覆盖原有词库。"
        panel.prompt = "导入"
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let result = session.importDictionary(url.path)
        report(result, detail: session.dictionaryOperationError)
        return result == IME_OK ? url : nil
    }
    @discardableResult
    static func exportFile(_ session: ImeSession) -> URL? {
        session.focusOut()
        let panel = NSSavePanel()
        ImeAppearance.applyTheme(to: panel)
        panel.title = "导出用户词库"
        panel.message = "将用户词条与学习记录保存为本地TSV文件。"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "lampyris-user-dictionary.tsv"
        panel.allowedContentTypes = [.tabSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let result = session.exportDictionary(url.path)
        report(result, detail: session.dictionaryOperationError)
        return result == IME_OK ? url : nil
    }
}
