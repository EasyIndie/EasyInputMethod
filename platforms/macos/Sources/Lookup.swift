import Cocoa

enum LookupUI {
    static func show(_ session: ImeSession) {
        session.focusOut()
        let alert = NSAlert()
        alert.messageText = "拼音反查"
        alert.informativeText = "输入汉字或词组，查询内置词表的首选读音。查询仅在本地进行。"
        alert.addButton(withTitle: "查询")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        input.placeholderString = "例如：你好"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let result = NSAlert()
        result.messageText = "拼音反查结果"
        result.informativeText = session.reverseLookup(input.stringValue) ?? "未收录此读音，请检查文本（最多 256 个 UTF-8 字节）。"
        result.runModal()
    }
}
