// 配置读取与路径约定。
//
// 配置唯一真值是 `config.toml`；宿主只读快照/取值，写入一律走 `ime_config_set`。
// 见 docs/配置架构.md 四条铁律（R1–R4）。

import Cocoa
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
    /// The configuration module owns parsing, aliases, validation and conflicts.
    static func hotkey(_ key: String) -> ConfiguredHotkey {
        let value = key.withCString { ime_config_hotkey($0) }
        return ConfiguredHotkey(kind: value.kind, modifiers: value.modifiers, key: value.key)
    }

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

    /// 单个观察者（持有处理器的弱引用 owner，owner 释放后自动失效）。
    private final class Observer {
        weak var owner: AnyObject?
        let handler: (String) -> Void
        init(owner: AnyObject, handler: @escaping (String) -> Void) {
            self.owner = owner
            self.handler = handler
        }
    }

    private var observers: [ObjectIdentifier: Observer] = [:]

    private init() {}

    /// 由 `owner` 接管回调；同一 `owner` 重复调用只替换处理器，不重复订阅。
    /// 支持多观察者（宿主与设置面板需各自响应，ADR-070）。
    func observe(owner: AnyObject, _ handler: @escaping (String) -> Void) {
        observers[ObjectIdentifier(owner)] = Observer(owner: owner, handler: handler)
        if token < 0 {
            token = ime_config_subscribe(configChangedBridge, nil)
        }
    }

    /// 仅移除 `owner` 自己的观察，不影响其它观察者。
    func clear(owner: AnyObject) {
        observers[ObjectIdentifier(owner)] = nil
    }

    fileprivate func deliver(_ key: String) {
        // 清理已释放的 owner，再快照处理器后派发（处理器可能再增删观察者）。
        for (id, observer) in observers where observer.owner == nil {
            observers[id] = nil
        }
        let handlers = observers.values.map(\.handler)
        for handler in handlers {
            handler(key)
        }
    }
}

/// AppKit adapter for a typed shortcut, shared by menus and input dispatch.
struct ConfiguredHotkey {
    let kind: UInt32
    private let modifierBits: UInt32
    let key: UInt32
    init(kind: UInt32, modifiers: UInt32, key: UInt32) {
        self.kind = kind; modifierBits = modifiers; self.key = key
    }
    var modifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for (bit, flag) in [(UInt32(1), NSEvent.ModifierFlags.control), (2, .option), (4, .shift), (8, .command)] {
            if modifierBits & bit != 0 { flags.insert(flag) }
        }
        return flags
    }
    var equivalent: String { UnicodeScalar(key).map { String($0) } ?? "" }
    func matches(_ event: NSEvent) -> Bool {
        guard kind == 2, event.modifierFlags.intersection([.control, .option, .shift, .command]) == modifiers else { return false }
        if key == 32 { return event.keyCode == 49 || event.charactersIgnoringModifiers == " " }
        return event.charactersIgnoringModifiers?.lowercased() == equivalent
    }
}

/// Temporary process-wide state, never persisted as user preferences.
final class ErrorNoticeGate {
    private var seen: [String: Set<String>] = [:]
    func claim(channel: String, message: String?) -> Bool {
        guard let message else { seen[channel] = nil; return false }
        return seen[channel, default: []].insert(message).inserted
    }
}

/// Serialize modal notices and discard queued messages that have already recovered.
final class ProcessErrorPresenter {
    static let shared = ProcessErrorPresenter()
    private let gate = ErrorNoticeGate()
    private var queue: [(String, String, String, () -> String?)] = []
    private var presenting = false
    private let display: (String, String) -> Void

    init(display: @escaping (String, String) -> Void = { title, message in
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }) { self.display = display }

    func update(channel: String, title: String, current: @escaping () -> String?) {
        let message = current()
        guard gate.claim(channel: channel, message: message), let message else { return }
        queue.append((channel, title, message, current))
        DispatchQueue.main.async { [weak self] in self?.drain() }
    }

    private func drain() {
        guard !presenting, !queue.isEmpty else { return }
        let (channel, title, message, current) = queue.removeFirst()
        guard current() == message else {
            if current() == nil { _ = gate.claim(channel: channel, message: nil) }
            drain()
            return
        }
        presenting = true
        display(title, message)
        presenting = false
        drain()
    }
}
