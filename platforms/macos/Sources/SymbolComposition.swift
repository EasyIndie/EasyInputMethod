import Foundation

/// 反引号前缀模式的宿主侧状态（U3-5 / ADR-349）。
///
/// 不进入核心引擎：候选由 `SymbolCatalog` 直接提供，数字/方向键/回车都在宿主处理。
struct SymbolCompositionState {
    enum Phase {
        case categories
        case items(SymbolCategory)
    }

    var phase: Phase?
    var page = 0
    var selected = 0

    var isActive: Bool { phase != nil }

    mutating func reset() {
        phase = nil
        page = 0
        selected = 0
    }

    var isEmojiCategory: Bool {
        if case .items(let category) = phase { return category.isEmoji }
        return false
    }
}
