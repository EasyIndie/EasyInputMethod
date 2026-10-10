// 快捷键与使用说明面板：内容读取**当前实际配置**，展示真正生效的按键。
//
// 从输入法菜单「快捷键与使用说明…」打开（T-MVP-… 用户可自助学习）。

import Cocoa

enum HelpUI {
    /// 把配置里的组合键写法转成可读文本（`none`/空 → 已关闭）。
    static func readable(_ setting: String?) -> String {
        guard let setting, !setting.isEmpty, setting != "none" else { return "（已关闭）" }
        if setting == "shift" { return "单独按 Shift" }
        let names: [String: String] = [
            "ctrl": "Ctrl", "shift": "Shift", "alt": "Option", "cmd": "Command",
        ]
        return setting.lowercased().split(separator: "+").map { part in
            let key = String(part)
            if key == "space" { return "空格" }
            return names[key] ?? key.uppercased()
        }.joined(separator: " + ")
    }

    static func text() -> String {
        let english = readable(ImeConfig.string("hotkey.toggle_english"))
        let width = readable(ImeConfig.string("hotkey.toggle_width"))
        let punctuation = readable(ImeConfig.string("hotkey.toggle_punctuation"))
        let mode = readable(ImeConfig.string("hotkey.toggle_mode"))
        let pageWithComma = ImeConfig.bool("candidate.page_with_comma")
        let count = ImeConfig.int("candidate.count") ?? 7
        return """
        【切换】（均可在 config.toml 修改）
          中/英切换        \(english)
          全角/半角        \(width)
          中/英标点        \(punctuation)
          输入模式循环     \(mode)   （混输 → 五笔 → 拼音）

        【输入与候选】
          空格             选第一个候选上屏（无候选时提交原码）
          回车             提交原始字母（不选候选）
          1–9              选择对应候选
          候选翻页         组合态 , / .：\(pageWithComma ? "开" : "关")；- / =；PageUp / PageDown
          退格             删除一个编码
          Esc              取消当前组合
          Shift + 字母     直接输入大写字母

        【其它】
          每页候选数       \(count)（改 config.toml 即时生效，无需重启）
          菜单            切换模式、用户词库增/导/出、拼音反查、关于
          配置与恢复      ~/Library/Application Support/Lampyris/config.toml
                          写坏或异常处理见 docs/故障恢复.md
        """
    }

    static func show() {
        let alert = NSAlert()
        alert.messageText = "快捷键与使用说明"
        alert.informativeText = "以下为**当前生效**的按键；改 config.toml 后立即生效。"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 470, height: 300))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text()
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        alert.accessoryView = scroll
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
