import Cocoa
import ime
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); exit(1)
}
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else { fail("private config") }
func save(_ image: NSBitmapImageRep?, _ name: String) {
    guard let data = image?.representation(using: .png, properties: [:]) else { fail("snapshot " + name) }
    do { try data.write(to: output.appendingPathComponent(name + ".png")) } catch { fail("snapshot output") }
}
for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    guard ImeConfig.setString("appearance.theme", theme), let appearance = NSAppearance(named: name) else { fail("theme") }
    for deleting in [false, true] {
        let (alert, form) = UserDictionaryUI.makeEntryAlert(mode: "pinyin", deleting: deleting)
        form.code.stringValue = "nihao"; form.text.stringValue = "你好"
        form.status.stringValue = UserDictionaryUI.entryError(IME_ERR_INVALID_INPUT, code: "A B", text: "你好")
        form.layoutSubtreeIfNeeded()
        guard form.scheme.indexOfSelectedItem == 1, form.code.stringValue == "nihao", form.text.stringValue == "你好",
              form.code.accessibilityLabel() == "完整编码", form.text.accessibilityLabel() == "词条文本",
              form.bounds.contains(form.status.frame), !alert.window.isVisible,
              !deleting || (alert.buttons[0].keyEquivalent.isEmpty && alert.buttons[1].keyEquivalent == "\r")
        else { fail("form states: scheme=\(form.scheme.indexOfSelectedItem), label=\(form.code.accessibilityLabel() ?? "nil"), status=\(form.status.frame), bounds=\(form.bounds), visible=\(alert.window.isVisible), keys=\(alert.buttons.map { $0.keyEquivalent })") }
        guard let rep = form.bitmapImageRepForCachingDisplay(in: form.bounds) else { fail("form snapshot") }
        form.appearance = appearance
        form.cacheDisplay(in: form.bounds, to: rep)
        var image: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance { image = ImeAppearance.opaqueSnapshot(rep, background: .windowBackgroundColor) }
        save(image, "\(deleting ? "delete" : "add")-\(theme)")
        LocalAcceptanceEvidence.record("tools.form." + theme + (deleting ? ".delete" : ".add"), expected: "私有表单保留非法输入/错误和标签，删除默认取消", actual: ["scheme": form.scheme.indexOfSelectedItem, "code": form.code.stringValue, "text": form.text.stringValue, "status": form.status.stringValue, "keys": alert.buttons.map(\.keyEquivalent)])
    }
    InfoWindow.preparePresentationForTesting(title: "诊断信息", text: AboutUI.text(), allowsCopy: true,
       links: [InfoLink(title: "反馈问题", url: FeedbackUI.issuesURL), InfoLink(title: "反馈漏洞", url: FeedbackUI.securityURL)])
    save(InfoWindow.renderSnapshotForTesting(appearance: appearance), "diagnostics-\(theme)")
    guard let icon = NSImage(contentsOfFile: "assets/icons/yinghuo-official-app.icns") else { fail("official icon") }
    save(AboutPanel.shared.renderForTesting(appearance: appearance, icon: icon), "about-\(theme)")
    guard !AboutPanel.shared.isVisibleForTesting else { fail("about offscreen") }
    guard let aboutWindow = NSApp.windows.first(where: { $0.title == "关于" }), let content = aboutWindow.contentView else { fail("about content") }
    let actions = content.subviews.compactMap { $0 as? NSButton }
    guard actions.map(\.title) == ["复制诊断", "反馈问题"],
          actions.allSatisfy({ $0.bezelStyle == .rounded && $0.controlSize == .regular }),
          let feedback = actions.last as? NSPopUpButton,
          feedback.itemTitles == ["反馈问题", "报告问题", "报告安全漏洞"] else { fail("native about action labels/styles") }
    guard feedback.alignment == .center,
          actions.allSatisfy({ $0.frame.width < 120 }),
          abs((actions.first!.frame.minX + feedback.frame.maxX) / 2 - content.bounds.midX) < 1 else { fail("about action sizing and centering") }
    // 旧版 AppKit 的下拉按钮 sizeToFit 会多留一大段宽度（macOS 13 实测 +71pt），
    // 且两个控件高度不同——要求宽度贴固有尺寸、两控件行中心一致。
    guard feedback.frame.width <= feedback.intrinsicContentSize.width + 1,
          abs(actions.first!.frame.midY - feedback.frame.midY) < 0.5 else { fail("about action width hugs title and row centers align") }
    LocalAcceptanceEvidence.record("tools.about." + theme, expected: "复制/反馈按钮无省略号，原生rounded/regular，反馈渠道完整，宽度贴固有尺寸且行中心对齐", actual: ["buttons": actions.map(\.title), "channels": feedback.itemTitles, "widths": actions.map { $0.frame.width }, "row_centers": actions.map { $0.frame.midY }, "visible": aboutWindow.isVisible])
    InfoWindow.simulateOpenForTesting(FeedbackUI.issuesURL, succeeded: false)
    guard InfoWindow.statusForTesting.contains("打开失败") else { fail("failed link state") }
    LocalAcceptanceEvidence.record("tools.link-fallback." + theme, expected: "模拟打开失败保留地址和可见失败反馈；未访问外链", actual: InfoWindow.statusForTesting)
    save(InfoWindow.renderSnapshotForTesting(appearance: appearance, minimum: true), "feedback-failure-\(theme)")
    InfoWindow.simulateOpenForTesting(FeedbackUI.issuesURL, succeeded: true)
    guard InfoWindow.statusForTesting.contains("默认浏览器") else { fail("success state") }
    LocalAcceptanceEvidence.record("tools.link-success." + theme, expected: "模拟打开成功状态；不等同真实外链打开", actual: InfoWindow.statusForTesting)
    InfoWindow.preparePresentationForTesting(title: "拼音反查结果", text: String(repeating: "中华人民共和国：zhong hua ren min gong he guo\n", count: 80), allowsCopy: true)
    save(InfoWindow.renderSnapshotForTesting(appearance: appearance, minimum: true), "lookup-long-\(theme)")
    guard !InfoWindow.isVisibleForTesting, InfoWindow.statusForTesting.isEmpty else { fail("offscreen/no stale status") }
}
guard let isolatedSession = ImeSession(wubiPath: "data/generated/wubi86-core.tsv", pinyinCharsPath: nil, pinyinWordsPath: nil) else { fail("private session") }
_ = isolatedSession.feed(119)
let originalBuffer = isolatedSession.buffer
let hiddenParent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                            styleMask: [.titled], backing: .buffered, defer: false)
var refusedHiddenParent = false
UserDictionaryUI.presentEntry(isolatedSession, deleting: false, on: hiddenParent) { saved in
    refusedHiddenParent = !saved
}
guard refusedHiddenParent, isolatedSession.buffer == originalBuffer,
      hiddenParent.attachedSheet == nil else { fail("closed parent mutated input or showed sheet") }
LocalAcceptanceEvidence.record("tools.hidden-parent", expected: "关闭的父窗拒绝sheet且不改变私有组合", actual: ["refused": refusedHiddenParent, "buffer": isolatedSession.buffer, "sheet_exists": hiddenParent.attachedSheet != nil])
let board = NSPasteboard.withUniqueName()
defer { board.releaseGlobally() }
guard InfoWindow.copy("独有诊断文本", to: board), board.string(forType: .string) == "独有诊断文本" else { fail("private copy") }
guard AboutPanel.shared.copyDiagnostics(to: board), board.string(forType: .string) == AboutUI.text(),
      AboutPanel.shared.statusForTesting == "诊断信息已复制", AboutUI.text().contains("GPL-3.0"), AboutUI.text().contains("零遥测") else { fail("about contract") }
LocalAcceptanceEvidence.record("tools.clipboard", expected: "诊断复制到命名私有剪贴板且提示诊断信息已复制", actual: ["private_board_matches": board.string(forType: .string) == AboutUI.text(), "status": AboutPanel.shared.statusForTesting])
print("PASS tools-presentation: real labelled form, destructive cancel, retained errors, about/lookup long content, native link fallback/success, private clipboard, hidden light/dark")
