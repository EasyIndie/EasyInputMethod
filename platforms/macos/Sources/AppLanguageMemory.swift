// 按应用记住中英状态（ADR-333）：只在内存里、随宿主进程存亡，不落盘、不进配置。

import Foundation

/// 「应用 → 上次是否处于英文状态」的有界记忆。
///
/// 终端、编辑器里切到英文后，换个输入框或切走再回来不必重切。
/// 这是**会话状态**而非偏好（`docs/配置架构.md` §5），所以不写 `config.toml`，也不写任何文件。
struct AppLanguageMemory {
    /// 最多记住的应用数；超出时丢掉最久没更新的。
    static let capacity = 64

    private var states: [String: Bool] = [:]
    private var order: [String] = []

    /// 记下某个应用当前的中英状态。空标识（拿不到 bundle id）不记。
    mutating func remember(_ english: Bool, for bundle: String?) {
        guard let bundle, !bundle.isEmpty else { return }
        states[bundle] = english
        order.removeAll { $0 == bundle }
        order.append(bundle)
        while order.count > Self.capacity {
            states[order.removeFirst()] = nil
        }
    }

    /// 某个应用上次的中英状态；没记过返回 `nil`（调用方保持默认，不强行切换）。
    func english(for bundle: String?) -> Bool? {
        guard let bundle, !bundle.isEmpty else { return nil }
        return states[bundle]
    }

    var count: Int { states.count }
}
