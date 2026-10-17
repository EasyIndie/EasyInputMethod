import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef?{var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil}
func str(_ e:AXUIElement,_ k:String)->String{attr(e,k) as? String ?? ""}
guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"cn.jokerhub.inputmethod.Lampyris").first else { print("NO_APP"); exit(1) }
let ax=AXUIElementCreateApplication(app.processIdentifier)
let wins=(attr(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? []
print("windows:", wins.count, wins.map{str($0,kAXTitleAttribute)})
