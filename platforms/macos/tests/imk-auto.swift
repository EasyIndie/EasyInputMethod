// 萤火虫 macOS 自动化测试辅助工具（AX / 鼠标事件 / 输入源 / IME 菜单）。
//
// 供 `run-panel-acceptance.sh`（⑦⑧⑨）与 `run-input-apps.sh`（⑩）复用。
// 只依赖系统框架（AppKit / ApplicationServices / Carbon），运行时由脚本用 swiftc 编译。
//
// 子命令：
//   current-source             打印当前输入源精确ID
//   select-exact <id>          精确恢复输入源（不允许前缀匹配）
//   select [id]                 选中输入源（默认萤火虫）
//   activate <bundle>           把指定 App 前置
//   frontmost                   打印前台 App 名
//   click <x> <y>               在屏幕坐标投递一次鼠标左键点击（CGEvent）
//   dump <bundle>               打印窗口内的控件（role/title/value/desc/坐标）
//   fields <bundle>             打印文本控件（title/value/desc/坐标）
//   buttons <bundle>            打印按钮（title/desc/坐标）
//   press <bundle> <title>      按下标题匹配的按钮
//   press-value <bundle> <val>  按下 value 匹配的元素
//   set <bundle> <old> <new>    把当前 value 为 old 的文本框设为 new
//   menu [title]                打印 IME 菜单项；给了 title 则点击匹配项
//
// 退出码：0 成功；2 用法错误；3 未找到目标。

import ApplicationServices
import AppKit
import Carbon
import Foundation

func attr(_ el: AXUIElement, _ key: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, key as CFString, &v) == .success ? v : nil
}
func str(_ v: CFTypeRef?) -> String { (v as? String) ?? "" }
func role(_ el: AXUIElement) -> String { str(attr(el, kAXRoleAttribute)) }
func point(_ el: AXUIElement) -> CGPoint {
    var p = CGPoint.zero
    if let v = attr(el, kAXPositionAttribute) { AXValueGetValue((v as! AXValue), .cgPoint, &p) }
    return p
}
func walk(_ el: AXUIElement, _ depth: Int, _ visit: (AXUIElement) -> Void) {
    if depth > 24 { return }
    visit(el)
    if let kids = attr(el, kAXChildrenAttribute) as? [AXUIElement] {
        for k in kids { walk(k, depth + 1, visit) }
    }
}
func elements(_ bundle: String) -> [AXUIElement]? {
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        ($0.bundleIdentifier ?? "") == bundle
    }) else { return nil }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var out: [AXUIElement] = []
    if let ws = attr(ax, kAXWindowsAttribute) as? [AXUIElement] {
        for w in ws { walk(w, 0) { out.append($0) } }
    } else {
        walk(ax, 0) { out.append($0) }
    }
    return out
}
func line(_ el: AXUIElement) -> String {
    let p = point(el)
    return "\(role(el))\t\(str(attr(el, kAXTitleAttribute)))\t\(str(attr(el, kAXValueAttribute)))\t"
        + "\(str(attr(el, kAXDescriptionAttribute)))\t\(Int(p.x)),\(Int(p.y))"
}
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(3)
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"

switch command {
case "current-source":
    let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    guard let property = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        fail("无法读取当前输入源")
    }
    print(Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String)
    exit(0)

case "select", "select-exact":
    let want = args.count > 1 ? args[1] : "cn.jokerhub.inputmethod.Lampyris.default"
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    func id(_ s: TISInputSource) -> String {
        guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
    }
    guard let target = list.first(where: { id($0) == want || (command == "select" && id($0).hasPrefix(want)) }) else {
        fail("未找到输入源：\(want)")
    }
    let status = TISSelectInputSource(target)
    print("select \(id(target)) status=\(status)")
    exit(status == noErr ? 0 : 3)

case "activate":
    guard args.count > 1,
        let app = NSWorkspace.shared.runningApplications.first(where: {
            ($0.bundleIdentifier ?? "") == args[1]
        }) else { fail("app 未运行：\(args.count > 1 ? args[1] : "?")") }
    print("activate \(app.activate())")
    exit(0)

case "frontmost":
    let name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    print(name)
    exit(0)

case "click":
    guard args.count > 2, let x = Double(args[1]), let y = Double(args[2]) else {
        fail("用法：click <x> <y>")
    }
    let src = CGEventSource(stateID: .hidSystemState)
    let pt = CGPoint(x: x, y: y)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?
        .post(tap: .cghidEventTap)
    exit(0)

case "dump", "fields", "buttons":
    guard args.count > 1 else { fail("用法：\(command) <bundle-id>") }
    guard let all = elements(args[1]) else { fail("app 未运行：\(args[1])") }
    let wanted: Set<String>
    if command == "fields" {
        wanted = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    } else if command == "buttons" {
        wanted = ["AXButton"]
    } else {
        wanted = [
            "AXWindow", "AXButton", "AXTextField", "AXTextArea", "AXComboBox", "AXStaticText",
            "AXPopUpButton", "AXCheckBox", "AXRadioButton", "AXIncrementor",
        ]
    }
    for el in all where wanted.contains(role(el)) { print(line(el)) }
    exit(0)

case "press":
    guard args.count > 2 else { fail("用法：press <bundle-id> <button-title>") }
    guard let all = elements(args[1]) else { fail("app 未运行：\(args[1])") }
    guard let target = all.first(where: { role($0) == "AXButton" && str(attr($0, kAXTitleAttribute)) == args[2] })
    else { fail("按钮未找到：\(args[2])") }
    print("press err=\(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
    exit(0)

case "press-value":
    guard args.count > 2 else { fail("用法：press-value <bundle-id> <value>") }
    guard let all = elements(args[1]) else { fail("app 未运行：\(args[1])") }
    guard let target = all.first(where: { str(attr($0, kAXValueAttribute)) == args[2] })
    else { fail("value 未找到：\(args[2])") }
    print("press err=\(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
    exit(0)

case "press-desc":
    guard args.count > 2 else { fail("用法：press-desc <bundle-id> <description>") }
    guard let all = elements(args[1]) else { fail("app 未运行：\(args[1])") }
    guard let target = all.first(where: { str(attr($0, kAXDescriptionAttribute)) == args[2] })
    else { fail("控件未找到：\(args[2])") }
    print("press err=\(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
    exit(0)

case "set":
    guard args.count > 3 else { fail("用法：set <bundle-id> <old-value> <new-value>") }
    guard let all = elements(args[1]) else { fail("app 未运行：\(args[1])") }
    let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    guard let target = all.first(where: {
        textRoles.contains(role($0)) && str(attr($0, kAXValueAttribute)) == args[2]
    }) else { fail("文本框未找到：\(args[2])") }
    let err = AXUIElementSetAttributeValue(target, kAXValueAttribute as CFString, args[3] as CFTypeRef)
    print("set err=\(err.rawValue)")
    exit(0)

case "close-windows":
    guard args.count > 1 else { fail("用法：close-windows <bundle-id>") }
    guard let app = NSWorkspace.shared.runningApplications.first(where: {
        ($0.bundleIdentifier ?? "") == args[1]
    }) else { fail("app 未运行：\(args[1])") }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    var closed = 0
    if let ws = attr(ax, kAXWindowsAttribute) as? [AXUIElement] {
        for w in ws {
            if let raw = attr(w, kAXCloseButtonAttribute) {
                _ = AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString)
                closed += 1
            }
        }
    }
    print("closed=\(closed)")
    exit(0)

case "menu":
    // IME 菜单挂在 TextInputMenuAgent 的 extras 菜单栏上（desc = 输入法名）。
    guard let agent = NSWorkspace.shared.runningApplications.first(where: {
        ($0.bundleIdentifier ?? "") == "com.apple.TextInputMenuAgent"
    }), let extras = attr(AXUIElementCreateApplication(agent.processIdentifier), "AXExtrasMenuBar")
    else { fail("找不到 TextInputMenuAgent 的输入菜单") }
    let bar: AXUIElement
    if let list = extras as? [AXUIElement], let first = list.first { bar = first } else {
        bar = extras as! AXUIElement
    }
    let items = (attr(bar, kAXChildrenAttribute) as? [AXUIElement]) ?? [bar]
    guard let ime = items.first(where: { str(attr($0, kAXDescriptionAttribute)).contains("萤火虫") })
    else { fail("输入菜单里没有萤火虫") }
    _ = AXUIElementPerformAction(ime, kAXPressAction as CFString)
    usleep(400_000)
    guard let menu = (attr(ime, kAXChildrenAttribute) as? [AXUIElement])?.first else { fail("菜单未展开") }
    let menuItems = (attr(menu, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    for item in menuItems { print(str(attr(item, kAXTitleAttribute))) }
    if args.count > 1 {
        guard let target = menuItems.first(where: { str(attr($0, kAXTitleAttribute)).contains(args[1]) })
        else { fail("菜单项未找到：\(args[1])") }
        print("press err=\(AXUIElementPerformAction(target, kAXPressAction as CFString).rawValue)")
    }
    exit(0)

default:
    print(
        "用法：imk-auto <select|activate|frontmost|click|dump|fields|buttons|press|press-value|set|menu> ..."
    )
    exit(2)
}
