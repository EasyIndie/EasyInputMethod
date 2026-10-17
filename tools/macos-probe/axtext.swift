import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef?{var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil}
func str(_ e:AXUIElement,_ k:String)->String{attr(e,k) as? String ?? ""}
func el(_ e:AXUIElement,_ k:String)->AXUIElement?{guard let v=attr(e,k),CFGetTypeID(v)==AXUIElementGetTypeID() else{return nil};return (v as! AXUIElement)}
let pidArg = CommandLine.arguments.count>2 ? (Int32(CommandLine.arguments[2]) ?? 0) : 0
let pid: pid_t = pidArg != 0 ? pid_t(pidArg) : NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.TextEdit" })?.processIdentifier ?? 0
if pid <= 0 { print("NO_TEXTEDIT_PID"); exit(1) }
let ax=AXUIElementCreateApplication(pid)
let wins=(attr(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? []
let focused = el(ax, kAXFocusedWindowAttribute)
guard let win = focused ?? el(ax,kAXMainWindowAttribute) ?? wins.first else { print("NO_WINDOW"); exit(1) }
if CommandLine.arguments.count>3 { print("window:", str(win,kAXTitleAttribute)) }
func findText(_ e:AXUIElement,_ depth:Int) -> AXUIElement? {
    if depth>6 { return nil }
    if str(e,kAXRoleAttribute) == kAXTextAreaRole { return e }
    if let cs=attr(e,kAXChildrenAttribute) as? [AXUIElement] { for c in cs { if let t=findText(c,depth+1) { return t } } }
    return nil
}
guard let area=findText(win,0) else { print("NO_TEXT_AREA"); exit(1) }
let mode=CommandLine.arguments.count>1 ? CommandLine.arguments[1] : "read"
if mode == "clear" { print("clear rc", AXUIElementSetAttributeValue(area, kAXValueAttribute as CFString, "" as CFTypeRef).rawValue) }
else if mode == "selectall" { print("select rc", AXUIElementSetAttributeValue(area, kAXSelectedTextAttribute as CFString, (str(area,kAXValueAttribute)) as CFTypeRef).rawValue) }
else { print(str(area,kAXValueAttribute)) }
