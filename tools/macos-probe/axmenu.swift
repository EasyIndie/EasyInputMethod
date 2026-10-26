import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef?{var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil}
func str(_ e:AXUIElement,_ k:String)->String{attr(e,k) as? String ?? ""}
func el(_ e:AXUIElement,_ k:String)->AXUIElement?{guard let v=attr(e,k),CFGetTypeID(v)==AXUIElementGetTypeID() else{return nil};return (v as! AXUIElement)}
guard let agent=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.TextInputMenuAgent").first else { print("NO_AGENT"); exit(1) }
let owner=AXUIElementCreateApplication(agent.processIdentifier)
AXUIElementSetMessagingTimeout(owner,2)
guard let bar=el(owner,"AXExtrasMenuBar"), let items=attr(bar,kAXChildrenAttribute) as? [AXUIElement], items.count==1 else { print("NO_BAR"); exit(1) }
let item=items[0]
func rootMenu()->AXUIElement? { (attr(item,kAXChildrenAttribute) as? [AXUIElement])?.first }
func menuChildren()->[AXUIElement] { guard let m=rootMenu() else { return [] }; return (attr(m,kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
// `dump` 打印的路径把菜单自身算作第 0 层，实际遍历从菜单的孩子开始；
// 两种写法都接受（`[0,1]` 与 `[1]` 都指第 2 个条目），避免调用方照抄 dump 后报 PATH_MISMATCH。
func normalized(_ path:[Int])->[Int] { path.first == 0 ? Array(path.dropFirst()) : path }
func resolve(_ path:[Int])->AXUIElement? {
    guard let m=rootMenu() else { return nil }
    var e=m
    for i in path { guard let cs=attr(e,kAXChildrenAttribute) as? [AXUIElement], cs.indices.contains(i) else { return nil }; e=cs[i] }
    return e
}
let args=CommandLine.arguments
let cmd=args.count>1 ? args[1] : "dump"
switch cmd {
case "open":
    for _ in 0..<5 { if menuChildren().count < 7 { _ = AXUIElementPerformAction(item,kAXPressAction as CFString) }; RunLoop.current.run(until:Date().addingTimeInterval(0.5)); if menuChildren().count >= 7 { break } }
    print("desc=\(str(item,kAXDescriptionAttribute)) items=\(menuChildren().count)")
case "close":
    if let m=rootMenu() { print("cancel=\(AXUIElementPerformAction(m,kAXCancelAction as CFString).rawValue)") }
case "dump":
    guard let m=rootMenu() else { print("NO_MENU"); exit(1) }
    func walk(_ e:AXUIElement,_ depth:Int,_ path:[Int]){
        if depth>0 && depth<=3 {
            print(path.map(String.init).joined(separator:"."), str(e,kAXRoleAttribute), "|t="+str(e,kAXTitleAttribute), "|en=\((attr(e,kAXEnabledAttribute) as? Bool) ?? false)", "|vis=\((attr(e,kAXVisibleChildrenAttribute) as? [AXUIElement])?.count ?? -1)", "|mark="+str(e,"AXMenuItemMarkChar"))
        }
        if depth<3, let cs=attr(e,kAXChildrenAttribute) as? [AXUIElement] { for (i,c) in cs.enumerated(){ walk(c,depth+1,path+[i]) } }
    }
    walk(m,1,[0])
case "press":
    guard let data=args[2].data(using:.utf8), let raw=try? JSONSerialization.jsonObject(with:data) as? [Int] else { print("BAD_ARGS"); exit(2) }
    let path=normalized(raw)
    if menuChildren().count < 7 { _ = AXUIElementPerformAction(item,kAXPressAction as CFString); RunLoop.current.run(until:Date().addingTimeInterval(0.6)) }
    guard let e=resolve(path) else { print("PATH_MISMATCH"); exit(3) }
    print("target \(str(e,kAXRoleAttribute)) title=\(str(e,kAXTitleAttribute))")
    print("press=\(AXUIElementPerformAction(e,kAXPressAction as CFString).rawValue)")
    RunLoop.current.run(until:Date().addingTimeInterval(0.8))
case "select":
    guard let data=args[2].data(using:.utf8), let raw=try? JSONSerialization.jsonObject(with:data) as? [Int], args.count>3 else { print("BAD_ARGS"); exit(2) }
    let path=normalized(raw)
    let wanted=args[3]
    if menuChildren().count < 7 { _ = AXUIElementPerformAction(item,kAXPressAction as CFString); RunLoop.current.run(until:Date().addingTimeInterval(0.6)) }
    guard let parent=resolve(path) else { print("PATH_MISMATCH"); exit(3) }
    _ = AXUIElementPerformAction(parent,kAXPressAction as CFString)
    RunLoop.current.run(until:Date().addingTimeInterval(0.7))
    guard let menus=attr(parent,kAXChildrenAttribute) as? [AXUIElement], let sub=menus.first else { print("NO_SUBMENU"); exit(4) }
    let kids=(attr(sub,kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? (attr(sub,kAXChildrenAttribute) as? [AXUIElement]) ?? []
    print("parent=\(str(parent,kAXTitleAttribute)) children=\(kids.map{str($0,kAXTitleAttribute)})")
    guard let child=kids.first(where:{str($0,kAXTitleAttribute)==wanted}) else { print("CHILD_NOT_FOUND"); exit(5) }
    print("child=\(wanted) enabled=\((attr(child,kAXEnabledAttribute) as? Bool) ?? false) press=\(AXUIElementPerformAction(child,kAXPressAction as CFString).rawValue)")
    RunLoop.current.run(until:Date().addingTimeInterval(0.8))
default: print("unknown")
}
