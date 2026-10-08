// 列出系统当前识别到的输入源，便于诊断「装好了但看不到」。
//
// 用法：swiftc -O list-input-sources.swift -o /tmp/list && /tmp/list
// 见 platforms/macos/README.md 排错一节。

import Carbon
import Foundation

func prop(_ src: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(src, key) else { return nil }
    let value = Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    return (value as? String) ?? "\(value)"
}

let onlyModes = CommandLine.arguments.contains("--modes")
let keyword = CommandLine.arguments.first { !$0.hasPrefix("-") && $0 != CommandLine.arguments[0] }

guard let rawList = TISCreateInputSourceList(nil, true) else {
    print("TISCreateInputSourceList 返回 nil")
    exit(1)
}
let list = rawList.takeRetainedValue() as! [TISInputSource]

var matched = 0
for src in list {
    let id = prop(src, kTISPropertyInputSourceID as CFString) ?? "?"
    let type = prop(src, kTISPropertyInputSourceType as CFString) ?? "?"
    let name = prop(src, kTISPropertyLocalizedName as CFString) ?? "?"
    let enabled = prop(src, kTISPropertyInputSourceIsEnabled as CFString) ?? "?"

    if let keyword, !id.localizedCaseInsensitiveContains(keyword),
        !name.localizedCaseInsensitiveContains(keyword)
    {
        continue
    }
    if onlyModes, type != (kTISTypeKeyboardInputMode as String) {
        continue
    }
    matched += 1
    print("\(enabled == "1" ? "已启用" : "未启用")  id=\(id)  name=\(name)")
}

print("---- 匹配 \(matched) / 共 \(list.count) 个输入源 ----")
if matched == 0 {
    print("提示：新增/更换输入法后必须【注销并重新登录】；macOS 只在登录时扫描输入法 bundle。")
}
