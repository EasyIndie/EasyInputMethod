import Cocoa

enum LookupUI {
    static func show(_ session: ImeSession) {
        session.focusOut()
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = "拼音反查"
        alert.informativeText = "输入汉字或词组，查询内置词表的首选读音。查询仅在本地进行。"
        alert.addButton(withTitle: "查询")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        input.placeholderString = "例如：你好"
        input.setAccessibilityLabel("待反查的汉字或词组")
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        while alert.runModal() == .alertFirstButtonReturn {
            guard let result = session.reverseLookup(input.stringValue) else {
                alert.informativeText = "未收录此读音，请检查文本（最多256个UTF-8字节）。输入已保留，可修改后重试。"
                continue
            }
            InfoWindow.show(title: "拼音反查结果", text: result, allowsCopy: true)
            return
        }
    }
}
