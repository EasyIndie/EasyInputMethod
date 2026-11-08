import Foundation

/// 键位图的数据模型：把"哪个键挂哪些字根"从视图里抽出来。
///
/// 数据来自 `modules/keymap/data/key-roots-<方案>.tsv`（构建期生成、bundle 内只读）。
/// 换方案（五笔 98 / 郑码 / 仓颉 …）= 加一份同 schema 的 TSV 并传对应 `schemeID`，视图不动。
/// `rows` 是物理键盘排布，与方案无关。
struct KeyRootLayout: Equatable {
    struct Entry: Equatable {
        /// 键名字根（键帽上强调显示的那一个字）。
        let keyName: String
        /// 该键归属的区（1 横、2 竖、3 撇、4 捺、5 折；0 表示无分区，如万能键 Z）。
        let zone: Int
        /// 该键上的其它字根，按使用频次降序（不含键名本身）。
        let roots: [String]
        /// 该键的助记口诀（可空）。
        let mnemonic: String
    }

    let schemeID: String
    let displayName: String
    /// 物理排布：上排 10 键、中排 9 键、下排 7 键。
    let rows: [[Character]]
    let entries: [Character: Entry]

    static let standardRows: [[Character]] = [
        ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
        ["Z", "X", "C", "V", "B", "N", "M"],
    ]

    /// 内置兜底：只有键名字根。数据文件缺失时仍能画出键位图。
    static let wubi86: KeyRootLayout = {
        let table: [(Character, String, Int)] = [
            ("G", "王", 1), ("F", "土", 1), ("D", "大", 1), ("S", "木", 1), ("A", "工", 1),
            ("H", "目", 2), ("J", "日", 2), ("K", "口", 2), ("L", "田", 2), ("M", "山", 2),
            ("T", "禾", 3), ("R", "白", 3), ("E", "月", 3), ("W", "人", 3), ("Q", "金", 3),
            ("Y", "言", 4), ("U", "立", 4), ("I", "水", 4), ("O", "火", 4), ("P", "之", 4),
            ("N", "已", 5), ("B", "子", 5), ("V", "女", 5), ("C", "又", 5), ("X", "纟", 5),
            ("Z", "万能", 0),
        ]
        var entries: [Character: Entry] = [:]
        for (letter, keyName, zone) in table {
            entries[letter] = Entry(keyName: keyName, zone: zone, roots: [], mnemonic: "")
        }
        return KeyRootLayout(schemeID: "wubi86", displayName: "五笔 86",
                             rows: standardRows, entries: entries)
    }()

    /// 解析一份 `scheme / letter / zone / keyname / roots` 的 TSV。
    static func parse(tsv: String, schemeID: String, displayName: String) -> KeyRootLayout? {
        var entries: [Character: Entry] = [:]
        for line in tsv.split(separator: "\n") {
            if line.hasPrefix("#") { continue }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 5, fields[0] == Substring(schemeID),
                  let letter = fields[1].first,
                  let zone = Int(fields[2]) else { continue }
            let roots = fields[4].split(separator: " ").map(String.init)
            let mnemonic = fields.count >= 6 ? String(fields[5]) : ""
            entries[letter] = Entry(keyName: String(fields[3]), zone: zone, roots: roots,
                                    mnemonic: mnemonic)
        }
        guard entries.count >= 25 else { return nil }
        return KeyRootLayout(schemeID: schemeID, displayName: displayName,
                             rows: standardRows, entries: entries)
    }

    /// 按区整理的口诀（每个区分一行，便于界面展示）。
    var mnemonicsByZone: [(zone: Int, name: String, text: String)] {
        let names = [1: "横区", 2: "竖区", 3: "撇区", 4: "捺区", 5: "折区", 0: "其它"]
        return (1...5).compactMap { zone in
            let text = rows.joined()
                .compactMap { entries[$0] }
                .filter { $0.zone == zone && !$0.mnemonic.isEmpty }
                .map(\.mnemonic)
                .joined(separator: "，")
            return text.isEmpty ? nil : (zone, names[zone] ?? "", text)
        }
    }

    /// 从 bundle 内只读文件加载；缺失或损坏时回落到内置键名字根表。
    static func load(schemeID: String = "wubi86",
                     displayName: String = "五笔 86",
                     resourceName: String = "key-roots-wubi86",
                     bundle: Bundle = .main) -> KeyRootLayout {
        let candidates = [bundle.url(forResource: resourceName, withExtension: "tsv"),
                          bundle.bundleURL.appendingPathComponent("Resources/\(resourceName).tsv"),
                          bundle.bundleURL.deletingLastPathComponent()
                              .appendingPathComponent("Resources/\(resourceName).tsv")]
        let text = candidates.compactMap { $0 }
            .first(where: { FileManager.default.fileExists(atPath: $0.path) })
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        guard let text, let layout = parse(tsv: text, schemeID: schemeID, displayName: displayName)
        else { return .wubi86 }
        return layout
    }
}
