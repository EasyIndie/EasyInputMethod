import Foundation

/// 学习区结构化提示（ADR-311 v2，`B0-runtime.tsv`）。
///
/// 资源在 App bundle 的 `Contents/Resources`：`字 \t 全码 \t 质量 \t 字根(形:键) \t 识别码(字母|末笔|结构) \t 简码(一/二)`。
/// **按需解析**：只常驻原始字节（约 120 KB）与"字 → 行区间"索引，命中时才解析单行并缓存最近若干条。
/// 一次性解析 3,000 条实测会让宿主多占 2–4 MiB，超出常驻预算（报告 256）。
/// 资源缺失或损坏时返回空表，学习区退回旧的 D14 数据（只读、不报错）。
struct LearningHint {
    let char: String
    let code: String?
    let quality: String
    let roots: [(glyph: String, key: String)]
    let recognition: (letter: String, stroke: String, structure: String)?
    let short1: String?
    let short2: String?

    var isPartial: Bool { quality == "partial" }
    var isUnknown: Bool { quality == "unknown" }
}

enum LearningHints {
    private static let store = Store()

    static func hint(for text: String) -> LearningHint? {
        guard text.count == 1 else { return nil }
        return store.hint(for: text)
    }

    /// 供测试与诊断：索引条目数（不等于已解析条数）。
    static var indexedCount: Int { store.indexedCount }
    static var materializedCount: Int { store.materializedCount }
    /// 可出题的字（`quality == full`），按文件顺序（字频降序）。练习用，首次访问时扫描一次。
    static var fullCharacters: [String] { store.fullCharacters }

    private final class Store {
        private let bytes: [UInt8]
        private let index: [String: Range<Int>]
        private var cache: [String: LearningHint] = [:]
        private let cacheLimit = 64
        private var fullCache: [String]?

        init() {
            let candidates = [Bundle.main.url(forResource: "B0-runtime", withExtension: "tsv"),
                              Bundle.main.bundleURL.appendingPathComponent("Resources/B0-runtime.tsv"),
                              Bundle.main.bundleURL.deletingLastPathComponent()
                                  .appendingPathComponent("Resources/B0-runtime.tsv")]
            let data = candidates.compactMap { $0 }
                .first(where: { FileManager.default.fileExists(atPath: $0.path) })
                .flatMap { try? Data(contentsOf: $0) }
            guard let data else {
                bytes = []
                index = [:]
                return
            }
            bytes = [UInt8](data)
            var table: [String: Range<Int>] = [:]
            table.reserveCapacity(3200)
            var start = 0
            while start < bytes.count {
                var end = start
                while end < bytes.count, bytes[end] != 0x0A { end += 1 }
                if end > start, bytes[start] != 0x23 {  // '#' 注释行跳过
                    var tab = start
                    while tab < end, bytes[tab] != 0x09 { tab += 1 }
                    if let char = String(bytes: bytes[start..<tab], encoding: .utf8), char.count == 1 {
                        table[char] = start..<end
                    }
                }
                start = end + 1
            }
            index = table
        }

        var indexedCount: Int { index.count }
        var materializedCount: Int { cache.count }

        /// 只读质量列判断是否 `full`，不解析整行。
        var fullCharacters: [String] {
            if let fullCache { return fullCache }
            var out: [String] = []
            out.reserveCapacity(index.count)
            for (char, range) in index {
                var field = 0
                var start = range.lowerBound
                var quality: ArraySlice<UInt8>?
                for position in range {
                    if bytes[position] == 0x09 {
                        field += 1
                        if field == 3 {
                            quality = bytes[start..<position]
                            break
                        }
                        start = position + 1
                    }
                }
                if let quality, quality.elementsEqual("full".utf8) { out.append(char) }
            }
            out.sort(by: { (index[$0]?.lowerBound ?? 0) < (index[$1]?.lowerBound ?? 0) })
            fullCache = out
            return out
        }

        func hint(for char: String) -> LearningHint? {
            if let cached = cache[char] { return cached }
            guard let range = index[char] else { return nil }
            guard let hint = Self.parse(bytes[range]) else { return nil }
            if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
            cache[char] = hint
            return hint
        }

        private static func parse(_ slice: ArraySlice<UInt8>) -> LearningHint? {
            var fields: [[UInt8]] = []
            var current: [UInt8] = []
            for byte in slice {
                if byte == 0x09 {
                    fields.append(current)
                    current = []
                } else {
                    current.append(byte)
                }
            }
            fields.append(current)
            guard fields.count == 6,
                  let char = String(bytes: fields[0], encoding: .utf8), char.count == 1,
                  let quality = String(bytes: fields[2], encoding: .utf8) else { return nil }
            let roots: [(String, String)] = String(bytes: fields[3], encoding: .utf8)?
                .split(separator: " ").compactMap { cell in
                    let parts = cell.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                    guard parts.count == 2, !parts[0].isEmpty, parts[1].count == 1 else { return nil }
                    return (String(parts[0]), parts[1].uppercased())
                } ?? []
            let recognition: (String, String, String)? = {
                let parts = (String(bytes: fields[4], encoding: .utf8) ?? "")
                    .split(separator: "|", omittingEmptySubsequences: false)
                guard parts.count == 3, !parts[0].isEmpty else { return nil }
                return (parts[0].uppercased(), String(parts[1]), String(parts[2]))
            }()
            let shorts = (String(bytes: fields[5], encoding: .utf8) ?? "")
                .split(separator: "/").map { $0.uppercased() }
            let code = String(bytes: fields[1], encoding: .utf8)
            return LearningHint(char: char,
                                code: (code?.isEmpty ?? true) ? nil : code?.uppercased(),
                                quality: quality,
                                roots: roots,
                                recognition: recognition,
                                short1: shorts.count > 0 ? shorts[0] : nil,
                                short2: shorts.count > 1 ? shorts[1] : nil)
        }
    }
}
