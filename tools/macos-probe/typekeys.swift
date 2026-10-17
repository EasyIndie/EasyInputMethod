import AppKit
let map: [Character: CGKeyCode] = ["a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,"1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"9":25,"7":26,"8":28,"0":29,"o":31,"u":32,"i":34,"p":35,"l":37,"j":38,"k":40,"n":45,"m":46]
let src=CGEventSource(stateID:.hidSystemState)
func press(_ code: CGKeyCode, _ text: String) {
    let d=CGEvent(keyboardEventSource:src,virtualKey:code,keyDown:true)
    let u=CGEvent(keyboardEventSource:src,virtualKey:code,keyDown:false)
    d?.post(tap:.cghidEventTap); usleep(60000); u?.post(tap:.cghidEventTap); usleep(150000)
}
for ch in CommandLine.arguments.dropFirst().joined(separator: " ") {
    if ch == " " { press(49, " "); continue }
    if ch == "\n" { press(36, "\r"); continue }
    guard let code = map[ch] else { print("unmapped \(ch)"); continue }
    press(code, String(ch))
}
