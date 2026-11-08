import Foundation

/// 离线练习（ADR-313）：只从 `full` 条目出题，本地判分，进度写本地有界 TSV。
///
/// 题型：一级简码 / 二级简码 / 完整码 / 识别码。数据复用 `LearningHints`（ADR-311）。
///
/// 三级简码需要"哪些字真有三级简码"的码表（引擎侧至今没收录，ADR-314 关闭），此处不提供，
/// 否则会把"前 3 码"当成三级简码教错。
enum PracticeKind: String, CaseIterable {
    case code1 = "code1"
    case code2 = "code2"
    case code = "code"
    case recognition = "recognition"

    var title: String {
        switch self {
        case .code1: return "一级简码"
        case .code2: return "二级简码"
        case .code: return "完整码"
        case .recognition: return "识别码"
        }
    }

    /// 需要用户敲字母的题型。
    var isTyping: Bool { self != .recognition }

    /// 该题型要求的答案（字母）；识别码题型没有字母答案。
    func answer(for question: PracticeQuestion) -> String? {
        switch self {
        case .code1: return question.short1
        case .code2: return question.short2
        case .code: return question.code
        case .recognition: return nil
        }
    }

    /// 提示语。
    func prompt(for question: PracticeQuestion) -> String {
        switch self {
        case .code1: return "打出它的一级简码（1 位）"
        case .code2: return "打出它的二级简码（2 位）"
        case .code: return "打出它的完整五笔码（\(question.code.count) 位）"
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

    /// 拆解提示：字根（带键位），未知字根显示 `？`。
    var rootHint: String {
        roots.map { "\($0.glyph)\($0.key)" }.joined(separator: " ")
    }
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

    @discardableResult
    func next() -> PracticeQuestion? {
        question = bank.randomElement()
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
