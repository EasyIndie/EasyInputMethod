import Foundation

/// 学习区结构化提示（ADR-311 v2，`B0-runtime.tsv`）。
///
/// 资源在 App bundle 的 `Contents/Resources`：`字 \t 全码 \t 质量 \t 字根(形:键) \t 识别码(字母|末笔|结构) \t 简码(一/二)`。
/// 缺失或损坏时返回空表，学习区退回旧的 D14 数据（只读、不报错）。
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
    static let shared: [String: LearningHint] = load()

    static func hint(for text: String) -> LearningHint? {
        guard text.count == 1 else { return nil }
        return shared[text]
    }

    private static func load() -> [String: LearningHint] {
        let candidates = [Bundle.main.url(forResource: "B0-runtime", withExtension: "tsv"),
                          Bundle.main.bundleURL.appendingPathComponent("Resources/B0-runtime.tsv"),
                          Bundle.main.bundleURL.deletingLastPathComponent()
                              .appendingPathComponent("Resources/B0-runtime.tsv")]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: LearningHint] = [:]
        out.reserveCapacity(3200)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, fields[0].count == 1 else { continue }
            let roots: [(String, String)] = fields[3].split(separator: " ").compactMap { cell in
                let parts = cell.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 2, !parts[0].isEmpty, parts[1].count == 1 else { return nil }
                return (parts[0], parts[1].uppercased())
            }
            let recognition: (String, String, String)? = {
                let parts = fields[4].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                guard parts.count == 3, !parts[0].isEmpty else { return nil }
                return (parts[0].uppercased(), parts[1], parts[2])
            }()
            let shorts = fields[5].split(separator: "/").map { $0.uppercased() }
            out[fields[0]] = LearningHint(
                char: fields[0],
                code: fields[1].isEmpty ? nil : fields[1].uppercased(),
                quality: fields[2],
                roots: roots,
                recognition: recognition,
                short1: shorts.count > 0 ? shorts[0] : nil,
                short2: shorts.count > 1 ? shorts[1] : nil)
        }
        return out
    }
}
