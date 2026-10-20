// Test-only latency sampler: poll the focused text area until its value changes, then print the
// elapsed milliseconds. Sampling only; it never posts events.
import AppKit
import ApplicationServices
import Foundation

func fail(_ message: String) -> Never {
    fputs("BLOCKED：\(message)\n", stderr)
    exit(3)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3, args[0] == "wait" else { fail("参数不符：wait <pid> <timeoutMs>") }
guard let pid = pid_t(args[1]) else { fail("pid 无效") }
guard let timeout = Double(args[2]), timeout > 0 else { fail("超时无效") }

func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
    return value
}

// 传入客户端（TextEdit）的 pid：读它自己的聚焦控件，避免系统级元素的歧义。
let application = AXUIElementCreateApplication(pid)
/// 自己读取初始值，避免把长文本通过命令行传进来。
func currentValue() -> String? {
    guard let focused = attribute(application, kAXFocusedUIElementAttribute),
          CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
    let element = focused as! AXUIElement
    guard attribute(element, kAXRoleAttribute) as? String == "AXTextArea" else { return nil }
    return attribute(element, kAXValueAttribute) as? String
}
var baseline: String?
for _ in 0..<200 {
    baseline = currentValue()
    if baseline != nil { break }
    usleep(5000)
}
guard let baseline else { fail("无法读取客户端文本框") }
let start = Date()
var changedAt: TimeInterval?
while Date().timeIntervalSince(start) * 1000 < timeout {
    if let value = currentValue(), value != baseline {
        changedAt = Date().timeIntervalSince(start) * 1000
        break
    }
    usleep(3000)
}
guard let elapsed = changedAt else { fail("超时未观察到文本变化") }
print(String(format: "%.1f", elapsed))
