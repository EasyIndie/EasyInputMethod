// 输入源（TIS）探针：查看已启用源、选中、启用/停用。
// 注意：macOS 13 起 TISEnableInputSource 对第三方输入法返回 0 但不生效（实测，报告 095），
// 首次添加仍必须在「系统设置 → 键盘 → 文字输入」里完成；本工具用于查看、选中与停用。
import Carbon
import Foundation

func id(_ s: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceID) else { return "?" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
}
func isEnabled(_ s: TISInputSource) -> Bool {
    guard let p = TISGetInputSourceProperty(s, kTISPropertyInputSourceIsEnabled) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
}
func current() -> String {
    id(TISCopyCurrentKeyboardInputSource().takeRetainedValue())
}
func find(_ wanted: String, includeAll: Bool) -> TISInputSource? {
    let list = TISCreateInputSourceList(nil, includeAll).takeRetainedValue() as! [TISInputSource]
    return list.first { id($0) == wanted }
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "list"
switch command {
case "list":
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as! [TISInputSource]
    for s in list where isEnabled(s) { print("enabled", id(s)) }
    print("current", current())
case "select":
    guard args.count > 2, let s = find(args[2], includeAll: false) else {
        print("missing", args.count > 2 ? args[2] : "(no id)"); exit(1)
    }
    print("select", id(s), TISSelectInputSource(s))
    print("current", current())
case "enable", "disable":
    guard args.count > 2 else { print("usage: tissrc enable|disable <id>"); exit(2) }
    guard let s = find(args[2], includeAll: true) else { print("missing", args[2]); exit(1) }
    let rc = command == "enable" ? TISEnableInputSource(s) : TISDisableInputSource(s)
    print(command, id(s), "rc=\(rc)", "enabled=\(isEnabled(s))")
    if command == "enable" && !isEnabled(s) {
        print("提示：macOS 13 起第三方输入法需要用户在「系统设置 → 键盘 → 文字输入」里添加")
        exit(1)
    }
default:
    print("usage: tissrc list|select <id>|enable <id>|disable <id>"); exit(2)
}
