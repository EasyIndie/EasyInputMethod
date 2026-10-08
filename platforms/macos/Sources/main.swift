// 萤火虫输入法 · macOS 宿主入口。
//
// IMKServer 按 Info.plist 的 InputMethodConnectionName 建立连接，并按
// InputMethodServerControllerClass 实例化 YinghuoInputController。

import Cocoa
import InputMethodKit
import ime

// 1) 设定唯一配置路径（必须早于任何其他配置调用）。
ime_config_init(ImePaths.configFile())

// 2) 启动 IMK 服务器；server 需在整个进程生命周期内保持存活。
let connectionName =
    (Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String)
    ?? "Yinghuo_InputMethod_Connection"
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
