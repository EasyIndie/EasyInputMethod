// 把合成按键直接投递到指定进程（用于自动化验收：GUI 会话里的测试窗口 + 受 TCC 信任的投递进程）。
import AppKit

let keys: [Character: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
    "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31,
    "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    " ": 49, ".": 47, ",": 43,
]

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    print("usage: keytopid <pid> <keys>")
    exit(2)
}
let useHID = args.contains("--hid")
let paceArgs = args.dropFirst().filter { $0 != "--hid" }
let argIndex = Array(paceArgs)
let paceHold = argIndex.count > 2 ? (UInt32(argIndex[2]) ?? 120) * 1000 : 120_000
let paceGap = argIndex.count > 3 ? (UInt32(argIndex[3]) ?? 180) * 1000 : 180_000
if useHID {
    let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
    if front != pid {
        print("NOT_FRONTMOST front=\(front) expected=\(pid)")
        exit(3)
    }
}
let source = CGEventSource(stateID: .hidSystemState)
let modifiers: [String: (CGKeyCode, CGEventFlags)] = [
    "shift": (56, .maskShift), "opt": (58, .maskAlternate), "ctrl": (59, .maskControl),
    "cmd": (55, .maskCommand),
]

func send(_ event: CGEvent?) {
    if useHID { event?.post(tap: .cghidEventTap) } else { event?.postToPid(pid) }
}

func tap(_ code: CGKeyCode, _ flags: CGEventFlags, hold: CGEventFlags = []) {
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags.union(hold)
    up?.flags = flags.union(hold)
    send(down)
    usleep(paceHold)
    send(up)
    usleep(paceGap)
}

// 语法：分号分隔的片段；每段为 [shift+|opt+|ctrl+]<字符> 或单独的 <修饰键名>（单击该修饰键）。
// 修饰键可用 <名字>c 形式（如 shiftc/optc）发出真正的 flagsChanged 事件，供只监听修饰键变化的热键使用。

func flagsChanged(_ code: CGKeyCode, down: CGEventFlags) {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    event?.type = .flagsChanged
    event?.flags = down
    send(event)
    usleep(paceHold)
    let release = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    release?.type = .flagsChanged
    release?.flags = []
    send(release)
    usleep(paceGap)
}
for token in args[2].split(separator: ";") {
    let parts = token.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
    if parts.count == 1, parts[0] == " " {
        tap(keys[" "]!, [])
        continue
    }
    if parts.count == 1, let modifier = modifiers[parts[0]] {
        tap(modifier.0, modifier.1)
        continue
    }
    if parts.count == 1, parts[0].hasSuffix("c"),
       let modifier = modifiers[String(parts[0].dropLast())] {
        flagsChanged(modifier.0, down: modifier.1)
        continue
    }
    if parts.count == 1, !parts[0].isEmpty, parts[0].allSatisfy({ keys[$0] != nil }) {
        for character in parts[0] { tap(keys[character]!, []) }
        continue
    }
    guard parts.count == 2, let modifier = modifiers[parts[0]], let code = keys[Character(parts[1])] else {
        print("skip token: \(token)")
        continue
    }
    let hold = modifier.1
    let modDown = CGEvent(keyboardEventSource: source, virtualKey: modifier.0, keyDown: true)
    let modUp = CGEvent(keyboardEventSource: source, virtualKey: modifier.0, keyDown: false)
    modDown?.flags = hold
    modUp?.flags = []
    send(modDown)
    usleep(paceHold)
    tap(code, hold, hold: hold)
    send(modUp)
    usleep(paceGap)
}
print("posted to \(pid)")
