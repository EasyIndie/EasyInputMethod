// 选择指定输入源（默认萤火虫）。供 run-imk-acceptance.sh 使用。
//
// 用法：im-select [TISInputSourceID]
// 退出码：0 成功；1 无法枚举；3 未找到。

import Carbon
import Foundation

let target =
    CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "cn.jokerhub.inputmethod.Lampyris.default"

guard let list = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource]
else {
    fputs("无法枚举输入源\n", stderr)
    exit(1)
}

func str(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
}

for source in list {
    guard let id = str(source, kTISPropertyInputSourceID), id.lowercased().contains("lampyris")
    else { continue }
    let status = TISSelectInputSource(source)
    print("select \(id) status=\(status)")
    if status == noErr { exit(0) }
}

fputs("未找到匹配的输入源（target=\(target)）\n", stderr)
exit(3)
