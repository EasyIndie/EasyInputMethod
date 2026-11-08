import Foundation

/// 键位图的数据模型：把"哪个键挂哪些字根"从视图里抽出来。
///
/// 目前唯一实现是五笔 86；换方案（五笔 98 / 郑码 / 仓颉 …）只需要再加一个 `KeyRootLayout`
/// 实例或一份 TSV，视图本身不用改。`rows` 是物理键盘排布，与方案无关。
struct KeyRootLayout {
    struct Entry {
        /// 键名字根（键帽上同时显示的字根，通常 1 个字）。
        let keyName: String
        /// 该键归属的区（1 横、2 竖、3 撇、4 捺、5 折；0 表示无分区，如万能键 Z）。
        let zone: Int
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
            entries[letter] = Entry(keyName: keyName, zone: zone)
        }
        return KeyRootLayout(schemeID: "wubi86", displayName: "五笔 86",
                             rows: standardRows, entries: entries)
    }()
}
