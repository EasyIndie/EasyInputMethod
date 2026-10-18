// 离屏渲染候选 / 关于 / 设置 / 诊断面板，供改 UI 时快速看效果。
// 不显示窗口、不读真实配置、不依赖安装包；由 `make macos-ui-snapshots` 调用。
//
// 同一文件编译出两个变体（脚本按 `-D` 切换），这样只调候选窗时不必重新编译设置面板：
//   默认        → 候选窗（candidate-single / pager / long / hint，亮暗各一份）
//   -DUI_PANELS → 关于 / 设置 / 诊断面板
import Cocoa
import ime

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK else {
    FileHandle.standardError.write(Data("FAIL: 私有配置初始化失败\n".utf8))
    exit(1)
}
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let themes: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
let caret = NSRect(x: 16, y: 20, width: 2, height: 20)
let area = NSRect(x: 0, y: 0, width: 1000, height: 800)

func save(_ rep: NSBitmapImageRep?, _ name: String) {
    guard let rep, let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("FAIL: \(name) 渲染失败\n".utf8))
        exit(1)
    }
    let url = output.appendingPathComponent(name + ".png")
    do { try data.write(to: url) } catch { exit(1) }
    print(String(format: "  %-28@ %4d×%-4d  %@", (name + ".png" as NSString), rep.pixelsWide, rep.pixelsHigh, url.path))
}

#if UI_PANELS

print("关于页")
guard let icon = NSImage(contentsOfFile: root.appendingPathComponent("icon.icns").path)
    ?? NSImage(named: NSImage.applicationIconName)
else {
    FileHandle.standardError.write(Data("FAIL: 缺少图标\n".utf8))
    exit(1)
}
for (theme, appearance) in themes {
    guard ImeConfig.setString("appearance.theme", theme) else { exit(1) }
    save(AboutPanel.shared.renderForTesting(appearance: NSAppearance(named: appearance)!, icon: icon),
         "about-\(theme)")
}

print("设置面板")
SettingsPanel.shared.prepare()
SettingsPanel.shared.bindSessionForTesting(nil)
for (theme, appearance) in themes {
    guard ImeConfig.setString("appearance.theme", theme) else { exit(1) }
    let rep = SettingsPanel.shared.renderSnapshotForTesting(appearance: NSAppearance(named: appearance)!)
    save(rep, "settings-\(theme)")
}

print("诊断面板")
InfoWindow.preparePresentationForTesting(title: "诊断信息", text: AboutUI.text(), allowsCopy: true,
    links: [InfoLink(title: "报告问题", url: FeedbackUI.issuesURL),
            InfoLink(title: "报告安全漏洞", url: FeedbackUI.securityURL)])
for (theme, appearance) in themes {
    guard ImeConfig.setString("appearance.theme", theme) else { exit(1) }
    save(InfoWindow.renderSnapshotForTesting(appearance: NSAppearance(named: appearance)!),
         "diagnostics-\(theme)")
}

print("PASS ui-snapshots(panels): 关于/设置/诊断离屏渲染完成，未显示窗口、未改动真实配置")

#else

let short = ["你", "尼", "呢", "泥", "拟"].map {
    ImeCandidate(text: $0, code: "wq", source: .codeTable, isPrefix: false)
}
let longWords = (0..<7).map {
    ImeCandidate(text: "中华人民共和国第" + String($0 + 1) + "项", code: "", source: .phrase, isPrefix: false)
}

func reportCandidate(_ window: CandidateWindow, _ theme: String, _ variant: String) {
    let pages = window.pageFramesForTesting
    let top = pages.count == 3 ? window.frame.height - pages[2].maxY : -1
    let bottom = window.candidateViewportFrameForTesting.minY
    print(String(format: "  ↳ %@/%@ 面板 %.0f×%.0f 顶/底留白 %.0f/%.0f 行高 %.0f 页码 %@",
                 variant, theme, window.frame.width, window.frame.height, top, bottom,
                 window.candidateViewportFrameForTesting.height,
                 window.pageStateForTesting.visible ? window.pageStateForTesting.text : "（单页）"))
}

print("候选窗")
for (theme, appearance) in themes {
    guard ImeConfig.setString("appearance.theme", theme) else { exit(1) }
    let window = CandidateWindow()
    window.setAppearanceForTesting(NSAppearance(named: appearance)!)
    window.update(candidates: short, input: "wq")
    window.layout(at: caret, within: area)
    save(window.renderSnapshotForTesting(), "candidate-single-\(theme)")
    reportCandidate(window, theme, "single")
    window.update(candidates: short, pageIndex: 0, pageCount: 55, input: "wq")
    window.layout(at: caret, within: area)
    save(window.renderSnapshotForTesting(), "candidate-pager-\(theme)")
    reportCandidate(window, theme, "pager")
    window.update(candidates: longWords, pageIndex: 0, pageCount: 2, input: "kwwl")
    window.layout(at: caret, within: area)
    save(window.renderSnapshotForTesting(), "candidate-long-\(theme)")
    reportCandidate(window, theme, "long")
    window.update(candidates: short, pageIndex: 0, pageCount: 55, input: "wq", hint: "键位提示：W 人 · Q 金")
    window.layout(at: caret, within: area)
    save(window.renderSnapshotForTesting(), "candidate-hint-\(theme)")
    reportCandidate(window, theme, "hint")
    window.hide()
}

print("PASS ui-snapshots(candidate): 候选窗离屏渲染完成，未显示窗口、未改动真实配置")

#endif
