import Foundation

/// 一个符号或 emoji 条目（U3-5 / ADR-349）。面板与候选窗共用同一份目录。
struct SymbolEntry {
    let category: String
    let text: String
    let name: String
    let keywords: String
}

struct EmojiEntry {
    let text: String
    let group: String
    let groupZh: String
    let order: Int
    let nameZh: String
    let nameEn: String
    let keywordsZh: String
    let keywordsEn: String
}

struct SymbolCategory {
    let id: String
    let title: String
    let isEmoji: Bool
}

enum PickerItem {
    case symbol(SymbolEntry)
    case emoji(EmojiEntry)

    var text: String {
        switch self {
        case .symbol(let entry): return entry.text
        case .emoji(let entry): return entry.text
        }
    }

    var name: String {
        switch self {
        case .symbol(let entry): return entry.name
        case .emoji(let entry): return entry.nameZh
        }
    }

    var detail: String {
        switch self {
        case .symbol(let entry): return entry.keywords
        case .emoji(let entry): return "\(entry.nameEn) · \(entry.keywordsZh)"
        }
    }

    var accessibilityLabel: String { "\(text) \(name)" }

    var searchText: String {
        switch self {
        case .symbol(let entry):
            return "\(entry.text) \(entry.name) \(entry.keywords)".lowercased()
        case .emoji(let entry):
            return "\(entry.text) \(entry.nameZh) \(entry.nameEn) \(entry.keywordsZh) \(entry.keywordsEn)"
                .lowercased()
        }
    }
}

/// 随包符号 / emoji 目录。首次使用时读取 TSV；缺失时给出可诊断错误，不联网。
final class SymbolCatalog {
    static let shared = SymbolCatalog()

    static let symbolCategories: [SymbolCategory] = [
        SymbolCategory(id: "punctuation", title: "标点", isEmoji: false),
        SymbolCategory(id: "math", title: "数学", isEmoji: false),
        SymbolCategory(id: "currency", title: "货币", isEmoji: false),
        SymbolCategory(id: "arrow", title: "箭头", isEmoji: false),
        SymbolCategory(id: "number", title: "序号", isEmoji: false),
        SymbolCategory(id: "misc", title: "其他", isEmoji: false),
    ]

    /// 前缀模式里的「emoji」入口；选中后打开面板。
    static let emojiEntry = SymbolCategory(id: "__emoji__", title: "emoji", isEmoji: true)

    private(set) lazy var symbols: [SymbolEntry] = loadSymbols()
    private(set) lazy var emoji: [EmojiEntry] = loadEmoji()
    private(set) var loadError: String?

    private(set) lazy var emojiGroups: [SymbolCategory] = {
        var seen = Set<String>()
        var groups: [SymbolCategory] = []
        for entry in emoji where !seen.contains(entry.group) {
            seen.insert(entry.group)
            groups.append(SymbolCategory(id: entry.group, title: entry.groupZh, isEmoji: true))
        }
        return groups
    }()

    var isAvailable: Bool { !symbols.isEmpty || !emoji.isEmpty }

    var prefixCategories: [SymbolCategory] { Self.symbolCategories + [Self.emojiEntry] }

    var allCategories: [SymbolCategory] { Self.symbolCategories + emojiGroups }

    func items(in category: SymbolCategory) -> [PickerItem] {
        if category.isEmoji {
            guard category.id != Self.emojiEntry.id else { return [] }
            return emoji.filter { $0.group == category.id }.map(PickerItem.emoji)
        }
        return symbols.filter { $0.category == category.id }.map(PickerItem.symbol)
    }

    func search(_ query: String) -> [PickerItem] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        let terms = needle.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        func matches(_ item: PickerItem) -> Bool {
            let text = item.searchText
            return terms.allSatisfy { text.contains($0) }
        }
        return symbols.map(PickerItem.symbol).filter(matches) + emoji.map(PickerItem.emoji).filter(matches)
    }

    // MARK: - 载入

    private func resourceURL(_ name: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: "tsv") { return url }
        let direct = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(name).tsv")
        return FileManager.default.fileExists(atPath: direct.path) ? direct : nil
    }

    private func lines(_ name: String) -> [String] {
        guard let url = resourceURL(name), let text = try? String(contentsOf: url, encoding: .utf8) else {
            loadError = "缺少 \(name).tsv；请重新安装完整包"
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    private func loadSymbols() -> [SymbolEntry] {
        var out: [SymbolEntry] = []
        // 注释以「# 」开头；符号 `#` 与 emoji `#️⃣` 的数据行不能被当成注释。
        for line in lines("symbols") where !line.isEmpty && line != "#" && !line.hasPrefix("# ") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4, !fields[1].isEmpty else { continue }
            out.append(SymbolEntry(category: fields[0], text: fields[1], name: fields[2],
                                   keywords: fields[3]))
        }
        return out
    }

    private func loadEmoji() -> [EmojiEntry] {
        var out: [EmojiEntry] = []
        for line in lines("emoji") where !line.isEmpty && line != "#" && !line.hasPrefix("# ") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 8, !fields[0].isEmpty else { continue }
            out.append(EmojiEntry(
                text: fields[0], group: fields[1], groupZh: fields[2],
                order: Int(fields[3]) ?? out.count, nameZh: fields[4], nameEn: fields[5],
                keywordsZh: fields[6], keywordsEn: fields[7]))
        }
        return out
    }
}
