import Cocoa
import UniformTypeIdentifiers
import ime

enum UserDictionaryUI {
    static func report(_ code: Int32) {
        guard code != IME_OK else { return }
        let alert = NSAlert()
        alert.messageText = "用户词库操作失败"
        alert.informativeText = "请检查词条格式、文件权限或锁文件。原有词库不会因无效导入被覆盖。（错误码：\(code)）"
        alert.runModal()
    }
    static func add(_ session: ImeSession) {
        session.focusOut()
        let alert = NSAlert()
        alert.messageText = "新增用户词条"
        alert.informativeText = "编码使用小写英文字母；拼音输入完整拼音，不加空格。"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")
        let scheme = NSPopUpButton(frame: NSRect(x: 0, y: 90, width: 300, height: 26))
        scheme.addItems(withTitles: ["五笔", "拼音"])
        scheme.selectItem(at: session.mode == "pinyin" ? 1 : 0)
        let code = NSTextField(frame: NSRect(x: 0, y: 50, width: 300, height: 26))
        code.placeholderString = "编码，例如 wqiy / nihao"
        let text = NSTextField(frame: NSRect(x: 0, y: 10, width: 300, height: 26))
        text.placeholderString = "词条文本"
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 125))
        for field in [scheme, code, text] as [NSView] { view.addSubview(field) }
        alert.accessoryView = view
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        report(session.addWord(scheme: scheme.indexOfSelectedItem == 0 ? "wubi" : "pinyin",
            code: code.stringValue, text: text.stringValue))
    }
    static func importFile(_ session: ImeSession) {
        session.focusOut()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        report(session.importDictionary(url.path))
    }
    static func exportFile(_ session: ImeSession) {
        session.focusOut()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "lampyris-user-dictionary.tsv"
        panel.allowedContentTypes = [.tabSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        report(session.exportDictionary(url.path))
    }
}
