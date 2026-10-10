// 配置读取与路径约定。
//
// 配置唯一真值是 `config.toml`；宿主只读快照/取值，写入一律走 `ime_config_set`。
// 见 docs/配置架构.md 四条铁律（R1–R4）。

import Foundation
import ime

enum ImePaths {
    /// 应用数据目录：`~/Library/Application Support/Lampyris/`（ADR-056）。
    static func supportDirectory() -> URL? {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first
        else { return nil }
        return base.appendingPathComponent("Lampyris", isDirectory: true)
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

    static func bool(_ key: String) -> Bool {
        string(key) == "true"
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

    /// 按 TOML 字面量写入（bool/int 等非字符串选项；字符串仍用 `setString`）。
    @discardableResult
    static func setToml(_ key: String, _ literal: String) -> Bool {
        key.withCString { keyPtr in
            literal.withCString { valuePtr in
                ime_config_set(keyPtr, valuePtr) == IME_OK
            }
        }
    }

    /// 最近一次配置加载/重载失败原因（含行号）；无错误返回 nil（ADR-059）。
    static func errorMessage() -> String? {
        guard let ptr = ime_config_last_error() else { return nil }
        let message = String(cString: ptr)
        return message.isEmpty ? nil : message
    }
}

/// `ime_config_subscribe` 的 C 回调：不在回调线程触碰 AppKit，一律转交主线程。
private func configChangedBridge(_ key: UnsafePointer<CChar>?, _ user: UnsafeMutableRawPointer?) {
    let changed = key.map { String(cString: $0) } ?? ""
    DispatchQueue.main.async { ConfigWatcher.shared.deliver(changed) }
}

/// 配置变更观察者：全进程只订阅一次，回调在主线程派发给当前所有者。
///
/// 见 ADR-058 / `docs/配置架构.md` §4、§11：外部改 `config.toml` 保存后，
/// 正在输入的候选窗应即时刷新，无需再按键。
final class ConfigWatcher {
    static let shared = ConfigWatcher()
    private var token: Int32 = -1
    private weak var owner: AnyObject?
    private var handler: ((String) -> Void)?

    private init() {}

    /// 由 `owner` 接管回调；重复调用只替换处理器，不重复订阅。
    func observe(owner: AnyObject, _ handler: @escaping (String) -> Void) {
        self.owner = owner
        self.handler = handler
        if token < 0 {
            token = ime_config_subscribe(configChangedBridge, nil)
        }
    }

    /// 仅当 `owner` 是当前所有者时解绑（避免多控制器互相误清）。
    func clear(owner: AnyObject) {
        guard self.owner === owner else { return }
        self.owner = nil
        self.handler = nil
    }

    fileprivate func deliver(_ key: String) {
        handler?(key)
    }
}
