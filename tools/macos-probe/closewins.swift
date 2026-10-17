import AppKit
import ApplicationServices
func attr(_ e:AXUIElement,_ k:String)->CFTypeRef?{var v:CFTypeRef?;return AXUIElementCopyAttributeValue(e,k as CFString,&v) == .success ? v:nil}
func str(_ e:AXUIElement,_ k:String)->String{attr(e,k) as? String ?? ""}
guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"cn.jokerhub.inputmethod.Lampyris").first else { print("NO_APP"); exit(1) }
let ax=AXUIElementCreateApplication(app.processIdentifier)
for w in (attr(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
    if let raw=attr(w,kAXCloseButtonAttribute), CFGetTypeID(raw)==AXUIElementGetTypeID() {
        _ = AXUIElementPerformAction(raw as! AXUIElement, kAXPressAction as CFString)
        print("closed", str(w,kAXTitleAttribute))
    }
}
print("left", ((attr(ax,kAXWindowsAttribute) as? [AXUIElement]) ?? []).map{str($0,kAXTitleAttribute)})
