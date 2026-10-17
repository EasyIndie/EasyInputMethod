import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef?{var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil}
func str(_ e:AXUIElement,_ k:String)->String{attr(e,k) as? String ?? ""}
func el(_ e:AXUIElement,_ k:String)->AXUIElement?{guard let v=attr(e,k),CFGetTypeID(v)==CFTypeID(AXUIElementGetTypeID()) || CFGetTypeID(v)==AXUIElementGetTypeID() else { return nil }; return (v as! AXUIElement)}
func point(_ e:AXUIElement,_ k:String)->CGPoint?{guard let v=attr(e,k),CFGetTypeID(v)==AXValueGetTypeID() else {return nil};var p=CGPoint.zero;return AXValueGetValue(v as! AXValue,.cgPoint,&p) ? p:nil}
func size(_ e:AXUIElement,_ k:String)->CGSize?{guard let v=attr(e,k),CFGetTypeID(v)==AXValueGetTypeID() else {return nil};var s=CGSize.zero;return AXValueGetValue(v as! AXValue,.cgSize,&s) ? s:nil}
guard let agent=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.TextInputMenuAgent").first else { print("NO_AGENT"); exit(1) }
let owner=AXUIElementCreateApplication(agent.processIdentifier)
AXUIElementSetMessagingTimeout(owner,2)
guard let bar=el(owner,"AXExtrasMenuBar"), let items=attr(bar,kAXChildrenAttribute) as? [AXUIElement], items.count==1 else { print("NO_BAR"); exit(1) }
let item=items[0]
func rootMenu()->AXUIElement? { (attr(item,kAXChildrenAttribute) as? [AXUIElement])?.first }
func menuChildren()->[AXUIElement] { guard let m=rootMenu() else { return [] }; return (attr(m,kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func resolve(_ path:[Int])->AXUIElement? { guard let m=rootMenu() else { return nil }; var e=m; for i in path { guard let cs=attr(e,kAXChildrenAttribute) as? [AXUIElement], cs.indices.contains(i) else { return nil }; e=cs[i] }; return e }
let args=CommandLine.arguments
let topMode = args.count >= 3 && args[1] == "top"
var path: [Int] = []
var wanted = ""
if topMode {
    wanted = args[2]
} else {
    guard args.count >= 3, let d = args[1].data(using: .utf8), let p = try? JSONSerialization.jsonObject(with: d) as? [Int] else { print("BAD_ARGS"); exit(2) }
    path = p
    wanted = args[2]
}
for _ in 0..<6 { if menuChildren().count < 7 { _ = AXUIElementPerformAction(item,kAXPressAction as CFString) }; RunLoop.current.run(until:Date().addingTimeInterval(0.5)); if menuChildren().count >= 7 { break } }
var kids: [AXUIElement] = []
if topMode {
    kids = menuChildren()
} else {
    guard let parent=resolve(path) else { print("PATH_MISMATCH"); exit(3) }
    _ = AXUIElementPerformAction(parent,kAXPressAction as CFString)
    RunLoop.current.run(until:Date().addingTimeInterval(0.7))
    guard let menus=attr(parent,kAXChildrenAttribute) as? [AXUIElement], let sub=menus.first else { print("NO_SUBMENU"); exit(4) }
    kids=(attr(sub,kAXVisibleChildrenAttribute) as? [AXUIElement]) ?? (attr(sub,kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
print("children:", kids.map{str($0,kAXTitleAttribute)})
guard let target=kids.first(where:{str($0,kAXTitleAttribute)==wanted}) else { print("CHILD_NOT_FOUND"); exit(5) }
guard let p=point(target,kAXPositionAttribute), let s=size(target,kAXSizeAttribute) else { print("NO_GEOMETRY"); exit(6) }
let cx=p.x+s.width/2, cy=p.y+s.height/2
print("target=\(wanted) rect=\(p.x),\(p.y) \(s.width)x\(s.height) click=\(cx),\(cy)")
if let shot=ProcessInfo.processInfo.environment["CLICK_SHOT"] { let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture"); p.arguments = ["-x", shot]; try? p.run(); p.waitUntilExit() }
let src=CGEventSource(stateID:.hidSystemState)
CGEvent(mouseEventSource:src,mouseType:.mouseMoved,mouseCursorPosition:CGPoint(x:cx,y:cy),mouseButton:.left)?.post(tap:.cghidEventTap)
usleep(120000)
let down=CGEvent(mouseEventSource:src,mouseType:.leftMouseDown,mouseCursorPosition:CGPoint(x:cx,y:cy),mouseButton:.left)
let up=CGEvent(mouseEventSource:src,mouseType:.leftMouseUp,mouseCursorPosition:CGPoint(x:cx,y:cy),mouseButton:.left)
down?.post(tap:.cghidEventTap); usleep(80000); up?.post(tap:.cghidEventTap)
print("clicked")
