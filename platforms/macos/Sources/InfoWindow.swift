// 菜单「反馈」「关于」共用的轻量只读信息窗口（ADR-077）。
//
// 与设置面板一致：不联网、不打开外部程序（ADR-074）；仅展示文本，可选一键复制。

import Cocoa

/// 单例信息窗口：换标题与正文复用同一个面板，避免多个窗口堆积。
final class InfoWindow: NSObject {
    private static let shared = InfoWindow()
    private var panel: NSPanel?
    private var currentText = ""

    static func show(title: String, text: String, allowsCopy: Bool) {
        shared.present(title: title, text: text, allowsCopy: allowsCopy)
    }

    private func present(title: String, text: String, allowsCopy: Bool) {
        currentText = text
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.title = title

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = text
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = false
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        var views: [NSView] = [scroll]
        if allowsCopy {
            let copy = NSButton(title: "复制反馈信息", target: self, action: #selector(copyText))
            copy.setContentHuggingPriority(.defaultHigh, for: .vertical)
            views.append(copy)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let content = panel.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -32),
        ])
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        _ = pasteboard.setString(currentText, forType: .string)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        return panel
    }
}

/// 关于信息（版本 / 构建 / 源码提交 / 许可）。
enum AboutUI {
    static func text() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        var commit = "未知"
        if let url = Bundle.main.resourceURL?.appendingPathComponent("SOURCE-COMMIT"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        {
            commit = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return [
            "萤火虫 Lampyris \(version)",
            "构建：\(build)",
            "源码提交：\(commit)",
            "许可证：GPL-3.0-or-later",
            "默认离线 · 零遥测 · 无账号",
        ].joined(separator: "\n")
    }

    static func show() {
        InfoWindow.show(title: "关于萤火虫", text: text(), allowsCopy: false)
    }
}
