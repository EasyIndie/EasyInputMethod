// 萤火虫输入法 · macOS 宿主入口。
//
// IMKServer 按 Info.plist 的 InputMethodConnectionName 建立连接，并按
// InputMethodServerControllerClass 实例化 LampyrisInputController。

import Cocoa
import InputMethodKit
import ime

// 1) 设定唯一配置路径（必须早于任何其他配置调用）。
ime_config_init(ImePaths.configFile())

// 1b) 校验 FFI ABI 版本：不匹配则拒绝启动，避免结构体布局不一致崩溃。
let expectedABI: UInt32 = 1
if ime_abi_version() != expectedABI {
    NSLog("萤火虫：FFI ABI 版本不匹配（期待 \(expectedABI)，实际 \(ime_abi_version())）")
    exit(1)
}

// 2) 启动 IMK 服务器；server 需在整个进程生命周期内保持存活。
let connectionName =
    (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String)
    ?? "cn.jokerhub.inputmethod.Lampyris_Connection"
guard let server = IMKServer(
    name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
else {
    NSLog("萤火虫：无法启动 IMKServer（connection=\(connectionName)）")
    exit(1)
}

// 3) 进入事件循环。
withExtendedLifetime(server) {
    NSApplication.shared.run()
}
