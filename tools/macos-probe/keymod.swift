import AppKit
let code=CGKeyCode(UInt16(CommandLine.arguments[1]) ?? 0)
var flags: CGEventFlags = []
for f in CommandLine.arguments.dropFirst(2).joined(separator: ",").split(separator: ",") {
    switch f { case "cmd": flags.insert(.maskCommand); case "ctrl": flags.insert(.maskControl); case "opt": flags.insert(.maskAlternate); case "shift": flags.insert(.maskShift); default: break }
}
let src=CGEventSource(stateID:.hidSystemState)
let d=CGEvent(keyboardEventSource:src,virtualKey:code,keyDown:true)
let u=CGEvent(keyboardEventSource:src,virtualKey:code,keyDown:false)
d?.flags=flags; u?.flags=flags
d?.post(tap:.cghidEventTap); usleep(60000); u?.post(tap:.cghidEventTap)
print("sent")
