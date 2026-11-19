import Foundation

/// 学习区结构化提示（ADR-311 v3，`B0-runtime.tsv`）。
///
/// 资源在 App bundle 的 `Contents/Resources`：`字 \t 全码 \t 质量 \t 字根(形:键) \t 识别码(字母|末笔|结构) \t 简码(一/二/三)`。
/// 简码列固定三个槽位、缺项写 `-`（ADR-376/377）：一/二/三级简码必须能被区分，否则「二级简码」题型永远
/// 出不到只有二级简码的字，三级简码也只能由练习侧另读一张表（两份来源＝学练漂移）。
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
    let short3: String?

    var isPartial: Bool { quality == "partial" }
    var isUnknown: Bool { quality == "unknown" }
}

extension LearningHint {
    /// 简码文案：带等级、缺项跳过（ADR-377）。旧实现只显示 `short1 ?? short2`，看不出等级，
    /// 而且三级简码根本读不到——练习考三级、学习区不显示，学与练就不一致（报告 304 F3）。
    var shortSummary: String? {
        var parts: [String] = []
        if let short1 { parts.append("一 " + short1.uppercased()) }
        if let short2 { parts.append("二 " + short2.uppercased()) }
        if let short3 { parts.append("三 " + short3.uppercased()) }
        return parts.isEmpty ? nil : "简码 " + parts.joined(separator: " · ")
    }
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
    /// 可出题的字（`quality != unknown`），按文件顺序（字频降序）。练习用，首次访问时扫描一次。
    ///
    /// ADR-378：口径从「只出 `full`」放宽到「不是 `unknown`」——简码题只考码、不缺拆解也能判分，
    /// 若只认 `full`，简码表里有拆法差异的字（二级 35 条、三级 210 条）永远练不到（报告 304 F5）。
    static var practiceCharacters: [String] { store.practiceCharacters }

    private final class Store {
        private let bytes: [UInt8]
        private let index: [String: Range<Int>]
        private var cache: [String: LearningHint] = [:]
        private let cacheLimit = 64
        private var practiceCache: [String]?

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

        /// 只读质量列判断是否可练（`!= unknown`），不解析整行。
        var practiceCharacters: [String] {
            if let practiceCache { return practiceCache }
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
                if let quality, !quality.elementsEqual("unknown".utf8) { out.append(char) }
            }
            out.sort(by: { (index[$0]?.lowerBound ?? 0) < (index[$1]?.lowerBound ?? 0) })
            practiceCache = out
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
            // 简码列固定三个槽位 `一级/二级/三级`，缺项写 `-`（ADR-376/377）。
            // 旧数据只写“存在的那些槽位”（如 `wb` 表示二级简码），单槽时按长度兜底：
            // 1 位=一级、2 位=二级、3 位=三级——否则二级简码会被当成一级简码。
            let shortSlots = (String(bytes: fields[5], encoding: .utf8) ?? "")
                .split(separator: "/", omittingEmptySubsequences: false)
                .map { $0.uppercased() }
            let short1: String?
            let short2: String?
            let short3: String?
            switch shortSlots.count {
            case 0:
                short1 = nil
                short2 = nil
                short3 = nil
            case 1:
                // 旧数据（v2）只写存在的槽位：按长度兜底判断等级。
                let only = shortSlots[0]
                short1 = only == "-" ? nil : (only.count == 1 ? only : nil)
                short2 = only == "-" ? nil : (only.count == 2 ? only : nil)
                short3 = only == "-" ? nil : (only.count == 3 ? only : nil)
            default:
                short1 = shortSlots[0] == "-" ? nil : shortSlots[0]
                short2 = shortSlots[1] == "-" ? nil : shortSlots[1]
                short3 = shortSlots.count > 2 && shortSlots[2] != "-" ? shortSlots[2] : nil
            }
            let code = String(bytes: fields[1], encoding: .utf8)
            return LearningHint(char: char,
                                code: (code?.isEmpty ?? true) ? nil : code?.uppercased(),
                                quality: quality,
                                roots: roots,
                                recognition: recognition,
                                short1: short1,
                                short2: short2,
                                short3: short3)
        }
    }
}
