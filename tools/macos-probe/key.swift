import AppKit
let src=CGEventSource(stateID:.hidSystemState)
let down=CGEvent(keyboardEventSource:src,virtualKey:0,keyDown:true)
let up=CGEvent(keyboardEventSource:src,virtualKey:0,keyDown:false)
down?.flags=[]; down?.post(tap:.cghidEventTap)
usleep(60000)
up?.flags=[]; up?.post(tap:.cghidEventTap)
print("posted")
