// 沙盒配置探针（ADR-260）：在开启 App Sandbox 的进程里按 ImePaths 同一规则
// （Application Support + Lampyris）走 ime-config 写配置；结果写到容器 tmp。
// 不请求网络、不触碰真实 Application Support。
import Cocoa
import ime

@main
struct SandboxProbe {
    static func main() {
        let resultURL = FileManager.default.temporaryDirectory.appendingPathComponent("sandbox-probe.json")
        var result: [String: Any] = [
            "home": NSHomeDirectory(),
            "temporary": FileManager.default.temporaryDirectory.path,
        ]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Lampyris", isDirectory: true)
        try? support.map { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: true) }
        let configPath = support?.appendingPathComponent("config.toml").path ?? ""
        result["config_path"] = configPath
        let initCode = configPath.withCString { ime_config_init($0) }
        result["init"] = initCode
        if initCode == IME_OK {
            let setCode = "candidate.count".withCString { key in
                "7".withCString { value in ime_config_set(key, value) }
            }
            result["set"] = setCode
            if let value = "candidate.count".withCString({ ime_config_get($0) }) {
                result["read"] = String(cString: value)
            }
        }
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        try? data.write(to: resultURL)
    }
}
