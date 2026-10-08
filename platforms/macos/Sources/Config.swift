// 配置读取与路径约定。
//
// 配置唯一真值是 `config.toml`；宿主只读快照/取值，写入一律走 `ime_config_set`。
// 见 docs/配置架构.md 四条铁律（R1–R4）。

import Foundation
import ime

enum ImePaths {
    /// 应用数据目录：`~/Library/Application Support/萤火虫/`。
    static func supportDirectory() -> URL? {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return nil }
        return base.appendingPathComponent("萤火虫", isDirectory: true)
    }

    /// 唯一配置文件路径（必要时创建父目录）。
    static func configFile() -> String {
        guard let dir = supportDirectory() else {
            return (NSHomeDirectory() as NSString).appendingPathComponent("config.toml")
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.toml").path
    }
}

/// 配置读取（经 `ime-config`，绝不自行解析 TOML）。
enum ImeConfig {
    static func string(_ key: String) -> String? {
        guard let ptr = key.withCString({ ime_config_get($0) }) else { return nil }
        return String(cString: ptr)
    }

    static func int(_ key: String) -> Int? {
        guard let value = string(key) else { return nil }
        return Int(value)
    }

    /// 按 Schema 校验后写入（唯一写入路径）；`mode` 等枚举值以 TOML 字面量传入。
    @discardableResult
    static func setString(_ key: String, _ value: String) -> Bool {
        let toml = "\"\(value)\""
        return key.withCString { keyPtr in
            toml.withCString { valuePtr in
                ime_config_set(keyPtr, valuePtr) == IME_OK
            }
        }
    }
}
