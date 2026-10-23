// 输入源注册/启用/禁用/切换的最小 helper；随 Lampyris.app 一起签名与公证。
// 只操作指定 bundle id 的自有输入源，不写 HIToolbox、不改用户其它输入法。
import Carbon
import Foundation

func identifier(_ source: TISInputSource) -> String {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func sources(includeAll: Bool) -> [TISInputSource] {
    TISCreateInputSourceList(nil, includeAll).takeRetainedValue() as! [TISInputSource]
}

func matching(_ bundleID: String, includeAll: Bool) -> [TISInputSource] {
    sources(includeAll: includeAll).filter {
        let value = identifier($0)
        return value == bundleID || value.hasPrefix(bundleID + ".")
    }
}

func current() -> String {
    identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    fputs("用法：LampyrisTIS register <app> | enable|disable|status <bundleID> | switch-abc\n", stderr)
    exit(2)
}
let command = arguments[0]
let value = arguments[1]

switch command {
case "register":
    let url = URL(fileURLWithPath: value).standardizedFileURL
    let status = TISRegisterInputSource(url as CFURL)
    print("register \(status)")
    exit(status == noErr ? 0 : 1)
case "enable", "disable":
    var failed = false
    for source in matching(value, includeAll: true) {
        let status = command == "enable" ? TISEnableInputSource(source) : TISDisableInputSource(source)
        print("\(command) \(identifier(source)) \(status)")
        if status != noErr { failed = true }
    }
    Thread.sleep(forTimeInterval: 0.4)
    let enabled = matching(value, includeAll: false).map(identifier)
    print("enabled \(enabled.joined(separator: ","))")
    exit(failed ? 1 : 0)
case "status":
    print("enabled " + matching(value, includeAll: false).map(identifier).joined(separator: ","))
    print("current " + current())
case "switch-abc":
    guard let abc = sources(includeAll: false).first(where: { identifier($0) == "com.apple.keylayout.ABC" }) else {
        print("missing-abc"); exit(1)
    }
    let status = TISSelectInputSource(abc)
    print("switch-abc \(status)")
    exit(status == noErr ? 0 : 1)
default:
    fputs("未知命令：\(command)\n", stderr)
    exit(2)
}
