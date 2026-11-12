import Foundation

/// 离线练习（ADR-313）：只从 `full` 条目出题，本地判分，进度写本地有界 TSV。
///
/// 题型：字根 / 一级简码 / 二级简码 / 完整码 / 词组 / 识别码，按入门到熟练的顺序排（ADR-332/334）。
/// 字根题取自键位字根表（`KeyRootLayout`），其余复用 `LearningHints`（ADR-311）。
///
/// 三级简码需要"哪些字真有三级简码"的码表（引擎侧至今没收录，ADR-314 关闭），此处不提供，
/// 否则会把"前 3 码"当成三级简码教错。
enum PracticeKind: String, CaseIterable {
    case roots = "roots"
    case code1 = "code1"
    case code2 = "code2"
    case code = "code"
    case phrase = "phrase"
    case recognition = "recognition"

    var title: String {
        switch self {
        case .roots: return "字根"
        case .code1: return "一级简码"
        case .code2: return "二级简码"
        case .code: return "完整码"
        case .phrase: return "词组"
        case .recognition: return "识别码"
        }
    }

    /// 需要用户敲字母的题型。
    var isTyping: Bool { self != .recognition }

    /// 该题型要求的答案（字母）；识别码题型没有字母答案。
    func answer(for question: PracticeQuestion) -> String? {
        switch self {
        case .roots: return question.code
        case .code1: return question.short1
        case .code2: return question.short2
        case .code, .phrase: return question.code
        case .recognition: return nil
        }
    }

    /// 提示语。
    func prompt(for question: PracticeQuestion) -> String {
        switch self {
        case .roots: return "这个字根在哪个键上？（1 位）"
        case .code1: return "打出它的一级简码（1 位）"
        case .code2: return "打出它的二级简码（2 位）"
        case .code: return "打出它的完整五笔码（\(question.code.count) 位）"
        case .phrase: return "打出这个词的词组码（4 位）"
        case .recognition: return "按上面的字根与键位，判断末笔与结构"
        }
    }
}

struct PracticeQuestion {
    let kind: PracticeKind
    let char: String
    let code: String
    let roots: [(glyph: String, key: String)]
    let recognition: (letter: String, stroke: String, structure: String)?
    let short1: String?
    let short2: String?

}

enum Practice {
    static let strokes = ["横", "竖", "撇", "捺", "折"]
    static let structures = ["左右", "上下", "杂合"]

    /// 识别码反查表（末笔 × 结构）。
    static func recognitionLetter(stroke: String, structure: String) -> String? {
        let rows = ["横": "GFD", "竖": "HJK", "撇": "TRE", "捺": "YUI", "折": "NBV"]
        guard let row = rows[stroke], let index = structures.firstIndex(of: structure),
              row.count == structures.count else { return nil }
        return String(Array(row)[index])
    }

    /// 出题范围：`full` 且带完整码与字根（可判分）。
    static func bank(kind: PracticeKind, limit: Int = 3000) -> [PracticeQuestion] {
        if kind == .roots { return rootBank(layout: KeyRootLayout.load()) }
        if kind == .phrase { return phraseBank }
        var out: [PracticeQuestion] = []
        for char in LearningHints.fullCharacters.prefix(limit) {
            guard let hint = LearningHints.hint(for: char), hint.quality == "full",
                  let code = hint.code, !hint.roots.isEmpty else { continue }
            if kind == .recognition, hint.recognition == nil { continue }
            if kind == .code1, hint.short1?.count != 1 { continue }
            if kind == .code2, hint.short2?.count != 2 { continue }
            out.append(PracticeQuestion(kind: kind, char: char, code: code,
                                        roots: hint.roots, recognition: hint.recognition,
                                        short1: hint.short1, short2: hint.short2))
        }
        return out
    }

    /// 字根题库：每个键的键名字根与其余字根各出一题，答案是所在键（ADR-332）。
    ///
    /// 按键盘行序、口诀顺序排列，结果确定；Z 是万能键，没有字根，不出题。
    static func rootBank(layout: KeyRootLayout) -> [PracticeQuestion] {
        var out: [PracticeQuestion] = []
        var seen = Set<String>()
        for letter in layout.rows.joined() where letter != "Z" {
            guard let entry = layout.entries[letter] else { continue }
            let key = String(letter)
            for glyph in [entry.keyName] + entry.roots where !glyph.isEmpty && seen.insert(glyph).inserted {
                out.append(PracticeQuestion(kind: .roots, char: glyph, code: key.lowercased(),
                                            roots: [(glyph: glyph, key: key)], recognition: nil,
                                            short1: nil, short2: nil))
            }
        }
        return out
    }

    /// 词组题库上限：只取最常用的一批，练的是取码规则而不是背词表。
    static let phraseLimit = 800

    /// 词组题库（ADR-334）：随包码表里最常用的 2–4 字词，答案是 4 位词组码。首次用到时读一次。
    static let phraseBank: [PracticeQuestion] = {
        let name = "wubi86-core.tsv"
        let bundle = Bundle.main
        let candidates = [bundle.resourceURL?.appendingPathComponent(name),
                          bundle.bundleURL.appendingPathComponent("Resources/\(name)"),
                          bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/\(name)")]
        guard let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return phraseBank(tsv: text, limit: phraseLimit)
    }()

    /// 从码表文本挑词组题：2–4 个字、4 位码，按权重降序（同权重按码、词排，结果确定）。
    static func phraseBank(tsv: String, limit: Int) -> [PracticeQuestion] {
        var rows: [(code: Substring, text: Substring, weight: Int)] = []
        for line in tsv.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[0].count == 4, (2...4).contains(fields[1].count),
                  let weight = Int(fields[2]) else { continue }
            rows.append((fields[0], fields[1], weight))
        }
        rows.sort { ($1.weight, $0.code, $0.text) < ($0.weight, $1.code, $1.text) }
        var seen = Set<Substring>()
        var out: [PracticeQuestion] = []
        for row in rows where seen.insert(row.text).inserted {
            let word = String(row.text), code = String(row.code)
            out.append(PracticeQuestion(kind: .phrase, char: word, code: code,
                                        roots: phraseParts(word: word, code: code), recognition: nil,
                                        short1: nil, short2: nil))
            if out.count >= limit { break }
        }
        return out
    }

    /// 词组取码规则：两字词各取前两码；三字词前两字各取首码、末字取前两码；四字词各取首码。
    /// 返回「每个字 → 它贡献的码」，供答后讲解；长度对不上规则时返回空（不乱讲）。
    static func phraseParts(word: String, code: String) -> [(glyph: String, key: String)] {
        let chars = word.map(String.init), letters = Array(code.uppercased())
        let spans: [Int]
        switch chars.count {
        case 2: spans = [2, 2]
        case 3: spans = [1, 1, 2]
        case 4: spans = [1, 1, 1, 1]
        default: return []
        }
        guard letters.count == 4 else { return [] }
        var index = 0
        return zip(chars, spans).map { glyph, span in
            defer { index += span }
            return (glyph: glyph, key: String(letters[index..<(index + span)]))
        }
    }

    /// 判分：敲码类题型（大小写与空白不敏感）。
    static func judgeCode(_ answer: String, question: PracticeQuestion) -> Bool {
        guard let expected = question.kind.answer(for: question) else { return false }
        return answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == expected.lowercased()
    }

    /// 判分：识别码（末笔 + 结构 → 字母）。
    static func judgeRecognition(stroke: String, structure: String, question: PracticeQuestion) -> Bool {
        guard let expected = question.recognition?.letter,
              let letter = recognitionLetter(stroke: stroke, structure: structure) else { return false }
        return letter == expected
    }
}

/// 本地进度（`practice.tsv`）：数据而非配置；有界、原子写、删除即重置。
final class PracticeProgress {
    struct Row { var attempts: Int; var correct: Int; var lastSeen: Int }
    static let maxRows = 3000
    static let maxBytes = 256 * 1024
    private(set) var rows: [String: Row] = [:]
    let url: URL

    init(url: URL) {
        self.url = url
        load()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Lampyris/practice.tsv")
    }

    private func key(_ char: String, _ kind: PracticeKind) -> String { "\(char)\t\(kind.rawValue)" }

    /// 某个字在某题型下的记录；没练过返回 `nil`。出题加权用（ADR-328）。
    func row(char: String, kind: PracticeKind) -> Row? { rows[key(char, kind)] }

    private func load() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count == 5, let attempts = Int(fields[2]), let correct = Int(fields[3]),
                  let last = Int(fields[4]) else { continue }
            rows["\(fields[0])\t\(fields[1])"] = Row(attempts: attempts, correct: correct, lastSeen: last)
        }
    }

    func record(char: String, kind: PracticeKind, correct: Bool, now: Int = Int(Date().timeIntervalSince1970)) {
        var row = rows[key(char, kind)] ?? Row(attempts: 0, correct: 0, lastSeen: now)
        row.attempts += 1
        if correct { row.correct += 1 }
        row.lastSeen = now
        rows[key(char, kind)] = row
        if rows.count > Self.maxRows {
            let drop = rows.sorted { $0.value.attempts < $1.value.attempts }.prefix(rows.count - Self.maxRows)
            for item in drop { rows[item.key] = nil }
        }
        save()
    }

    /// 原子写：先写临时文件再替换；失败保留旧文件。
    func save() {
        var lines = ["# 萤火虫练习进度 v1：字\t题型\t次数\t正确\t最近时间（离线，可删除重置）"]
        for (key, row) in rows.sorted(by: { $0.key < $1.key }) {
            lines.append("\(key)\t\(row.attempts)\t\(row.correct)\t\(row.lastSeen)")
        }
        var payload = lines.joined(separator: "\n") + "\n"
        if payload.utf8.count > Self.maxBytes {
            payload = String(payload.prefix(Self.maxBytes / 2)) + "\n"
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".practice.tsv.\(UUID().uuidString)")
        do {
            try payload.write(to: temporary, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    /// 某个题型的统计：已练字数、总次数、正确次数。
    func stats(kind: PracticeKind) -> (practiced: Int, attempts: Int, correct: Int) {
        var practiced = 0, attempts = 0, correct = 0
        for (key, row) in rows {
            let fields = key.split(separator: "\t")
            guard fields.count == 2, fields[1] == Substring(kind.rawValue) else { continue }
            practiced += 1
            attempts += row.attempts
            correct += row.correct
        }
        return (practiced, attempts, correct)
    }

    /// 删除全部进度（重置）。
    func reset() {
        rows = [:]
        try? FileManager.default.removeItem(at: url)
    }

    var summary: String {
        let attempts = rows.values.reduce(0) { $0 + $1.attempts }
        let correct = rows.values.reduce(0) { $0 + $1.correct }
        guard attempts > 0 else { return "还没有练习记录" }
        return "已练 \(rows.count) 字 · \(attempts) 次 · 正确率 \(correct * 100 / attempts)%"
    }
}


/// 一局练习的纯逻辑（无 AppKit），便于自动化测试跑通流程。
final class PracticeSession {
    struct Result {
        let correct: Bool
        let explanation: String
    }

    private(set) var kind: PracticeKind
    private(set) var question: PracticeQuestion?
    private let progress: PracticeProgress
    private(set) var bank: [PracticeQuestion] = []

    init(kind: PracticeKind, progress: PracticeProgress) {
        self.kind = kind
        self.progress = progress
        reload()
    }

    func switchKind(_ kind: PracticeKind) {
        self.kind = kind
        reload()
    }

    func reload() {
        bank = Practice.bank(kind: kind)
        question = nil
        next()
    }

    /// 出题权重（ADR-328）：错过的字多出、没练过的字优先于已掌握的字。
    ///
    /// 「欠账」= 错 1 次记 2、对 1 次还 1，封顶 4；即错一次要连对两次才回到基准。
    /// 只读 `practice.tsv` 已有的三列，不新增落盘内容，也不参与候选排序。
    static func weight(for row: PracticeProgress.Row?) -> Int {
        guard let row, row.attempts > 0 else { return 2 }
        let wrong = max(0, row.attempts - row.correct)
        let debt = min(4, max(0, wrong * 2 - row.correct))
        return 1 + debt * 4
    }

    /// 按权重抽下一题；题库多于一题时不连出同一个字。`pick` 仅供测试注入（参数为总权重，返回 `0..<总权重`）。
    @discardableResult
    func next(pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> PracticeQuestion? {
        let previous = question?.char
        let pool = bank.count > 1 ? bank.filter { $0.char != previous } : bank
        let weights = pool.map { Self.weight(for: progress.row(char: $0.char, kind: kind)) }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            question = nil
            return nil
        }
        var remaining = min(max(0, pick(total)), total - 1)
        question = pool.last
        for (candidate, weight) in zip(pool, weights) {
            if remaining < weight {
                question = candidate
                break
            }
            remaining -= weight
        }
        return question
    }

    /// 提交打字答案；`nil` 表示没有题目。
    func submitCode(_ answer: String) -> Result? {
        guard let question else { return nil }
        let correct = Practice.judgeCode(answer, question: question)
        progress.record(char: question.char, kind: kind, correct: correct)
        // 码值统一在答案区展示，这里只回对错，避免同一信息出现两次。
        return Result(correct: correct, explanation: "")
    }

    /// 提交识别码选择；证据说明用**正确**的末笔与结构，而不是用户选的。
    func submitRecognition(stroke: String, structure: String) -> Result? {
        guard let question, let expected = question.recognition else { return nil }
        let correct = Practice.judgeRecognition(stroke: stroke, structure: structure, question: question)
        progress.record(char: question.char, kind: kind, correct: correct)
        _ = expected
        return Result(correct: correct, explanation: "")
    }

    var summary: String { progress.summary }
}
