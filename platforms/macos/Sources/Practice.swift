import Foundation

/// 离线练习（ADR-313）：只从 `full` 条目出题，本地判分，进度写本地有界 TSV。
///
/// 题型：字根 / 一级简码 / 二级简码 / 三级简码 / 完整码 / 词组 / 识别码，按入门到熟练的顺序排（ADR-332/334/361）。
/// 字根题取自键位字根表（`KeyRootLayout`），其余复用 `LearningHints`（ADR-311）；
/// 三级简码用随包的 D17-ter 权威表（ADR-345），只对表里明确收录的字出题，不把"前 3 码"当简码。
enum PracticeKind: String, CaseIterable {
    case roots = "roots"
    case code1 = "code1"
    case code2 = "code2"
    case code3 = "code3"
    case code = "code"
    case phrase = "phrase"
    case recognition = "recognition"

    var title: String {
        switch self {
        case .roots: return "字根"
        case .code1: return "一级简码"
        case .code2: return "二级简码"
        case .code3: return "三级简码"
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
        case .code3: return question.short3
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
        case .code3: return "打出它的三级简码（3 位）"
        case .code: return "打出它的完整五笔码（\(question.code.count) 位）"
        case .phrase: return "打出这个词的词组码（4 位）"
        case .recognition: return "按上面的字根与键位，判断末笔与结构"
        }
    }
}

struct PracticeQuestion {
    let kind: PracticeKind
    let char: String

    /// 固定答案：字根题是键位、词组题是 4 位词码。`nil` = 答案与讲解都从学习区资源按需取。
    private let fixedCode: String?
    private let fixedRoots: [(glyph: String, key: String)]
    private let fixedRecognition: (letter: String, stroke: String, structure: String)?

    /// 懒题（报告 328 / ADR-386）：题库只常驻「题型 + 字」，答案/字根/简码/识别码用到才解析。
    /// 以前 5,021 道题每题都把码、字根数组、识别码、三条简码各存一份，宿主因此多占约 11 MiB。
    init(kind: PracticeKind, char: String) {
        self.kind = kind
        self.char = char
        self.fixedCode = nil
        self.fixedRoots = []
        self.fixedRecognition = nil
    }

    /// 固定答案的题（字根 / 词组）：这些题的答案不在学习区资源里。
    init(kind: PracticeKind, char: String, code: String,
         roots: [(glyph: String, key: String)],
         recognition: (letter: String, stroke: String, structure: String)?) {
        self.kind = kind
        self.char = char
        self.fixedCode = code
        self.fixedRoots = roots
        self.fixedRecognition = recognition
    }

    private var hint: LearningHint? { fixedCode == nil ? LearningHints.hint(for: char) : nil }
    var code: String { fixedCode ?? hint?.code ?? "" }
    var roots: [(glyph: String, key: String)] { fixedCode == nil ? (hint?.roots ?? []) : fixedRoots }
    var recognition: (letter: String, stroke: String, structure: String)? {
        fixedCode == nil ? hint?.recognition : fixedRecognition
    }
    var short1: String? { hint?.short1 }
    var short2: String? { hint?.short2 }
    /// 三级简码（D17-ter）：来自运行时资源同一行（ADR-377），不再另读一张表。
    var short3: String? { hint?.short3 }
}

enum Practice {
    static let strokes = ["横", "竖", "撇", "捺", "折"]
    static let structures = ["左右", "上下", "杂合"]

    struct KindStats {
        let practiced: Int
        let attempts: Int
        let correct: Int
    }

    /// 掌握一个题型需要的不同字数：最多 30；题库不足 30 时按题库数（一级简码只有 25 字）。
    static func requiredPractice(bankSize: Int) -> Int {
        min(30, max(1, bankSize))
    }

    /// 「掌握」口径（ADR-344/350）：练过的不同字数达到要求，且正确率 ≥90%。
    static func isMastered(_ stats: KindStats, bankSize: Int) -> Bool {
        guard stats.attempts > 0 else { return false }
        return stats.practiced >= requiredPractice(bankSize: bankSize)
            && stats.correct * 10 >= stats.attempts * 9
    }

    /// 分阶段解锁（ADR-350）：按题型顺序逐级解锁；已有练习记录的题型不会回锁。
    /// `staged == false` 时全部解锁（旧行为）。
    static func unlockedKinds(stats: [PracticeKind: KindStats], bankSizes: [PracticeKind: Int],
                              staged: Bool) -> Set<PracticeKind> {
        let kinds = PracticeKind.allCases
        guard staged else { return Set(kinds) }
        var unlocked: Set<PracticeKind> = []
        var previousMastered = true
        for kind in kinds {
            let current = stats[kind] ?? KindStats(practiced: 0, attempts: 0, correct: 0)
            if previousMastered || current.attempts > 0 { unlocked.insert(kind) }
            previousMastered = isMastered(current, bankSize: bankSizes[kind] ?? 30)
        }
        return unlocked
    }

    /// 进阶提示（ADR-344）：某题型达到「掌握」时，建议进入下一题型。
    /// 不强制；返回下一题型的标题；未达标或已是最后一档返回 `nil`。
    static func nextHint(kind: PracticeKind, practiced: Int, attempts: Int, correct: Int,
                         bankSize: Int = 30) -> String? {
        let stats = KindStats(practiced: practiced, attempts: attempts, correct: correct)
        guard isMastered(stats, bankSize: bankSize) else { return nil }
        let kinds = PracticeKind.allCases
        guard let index = kinds.firstIndex(of: kind), index + 1 < kinds.count else { return nil }
        return kinds[index + 1].title
    }

    /// 识别码反查表（末笔 × 结构）。
    static func recognitionLetter(stroke: String, structure: String) -> String? {
        let rows = ["横": "GFD", "竖": "HJK", "撇": "TRE", "捺": "YUI", "折": "NBV"]
        guard let row = rows[stroke], let index = structures.firstIndex(of: structure),
              row.count == structures.count else { return nil }
        return String(Array(row)[index])
    }

    /// 出题范围：有全码、且拆解不是 `unknown`（可判分、也讲得出为什么）。
    ///
    /// 覆盖口径（报告 304 F5/F8）：
    /// - 简码题只要求对应简码槽存在 → 简码表里的字都能练，不因拆解 `partial` 被丢掉；
    /// - `完整码`题允许无字根（键名字/成字字根），它们的规则是「连打四次」「报户口 + 笔画」；
    /// - `识别码`题要求有识别码；`字根`题走键位图题库，不依赖运行时资源。
    static func bank(kind: PracticeKind, limit: Int = 8000) -> [PracticeQuestion] {
        if kind == .roots { return rootBank(layout: KeyRootLayout.load()) }
        if kind == .phrase { return phraseBank }
        var out: [PracticeQuestion] = []
        out.reserveCapacity(min(limit, LearningHints.indexedCount))
        for char in LearningHints.practiceCharacters.prefix(limit) {
            guard let slots = LearningHints.slots(for: char) else { continue }
            switch kind {
            case .recognition: guard slots.hasRecognition else { continue }
            case .code1: guard slots.short1 else { continue }
            case .code2: guard slots.short2 else { continue }
            case .code3: guard slots.short3 else { continue }
            case .code, .roots, .phrase: break
            }
            out.append(PracticeQuestion(kind: kind, char: char))
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
                                            roots: [(glyph: glyph, key: key)], recognition: nil))
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
    ///
    /// 报告 328：以前把整张表（5.2 万行）一次性 `split` 成数组再排序，峰值与残留让宿主多占约 5 MiB；
    /// 现在逐行扫描 + 只保留权重最高的 `limit` 行（有界小顶堆），并只把入选行转成 String。
    static func phraseBank(tsv: String, limit: Int) -> [PracticeQuestion] {
        struct Row { let code: String; let text: String; let weight: Int }
        // 「更差」= 权重更低；同权重时码更大；再同则词更大。堆顶永远是最差的那行。
        func worse(_ a: Row, _ b: Row) -> Bool {
            if a.weight != b.weight { return a.weight < b.weight }
            if a.code != b.code { return a.code > b.code }
            return a.text > b.text
        }
        guard limit > 0 else { return [] }
        var heap: [Row] = []
        heap.reserveCapacity(limit + 1)
        var index = tsv.startIndex
        while index < tsv.endIndex {
            let end = tsv[index...].firstIndex(of: "\n") ?? tsv.endIndex
            let line = tsv[index..<end]
            index = end < tsv.endIndex ? tsv.index(after: end) : tsv.endIndex
            guard !line.hasPrefix("#") else { continue }
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[0].count == 4, (2...4).contains(fields[1].count),
                  let weight = Int(fields[2]) else { continue }
            let candidate = Row(code: String(fields[0]), text: String(fields[1]), weight: weight)
            if heap.count < limit {
                heap.append(candidate)
                var child = heap.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    guard worse(heap[child], heap[parent]) else { break }
                    heap.swapAt(child, parent)
                    child = parent
                }
            } else if worse(heap[0], candidate) {
                heap[0] = candidate
                var parent = 0
                while true {
                    let left = parent * 2 + 1, right = left + 1
                    var worst = parent
                    if left < heap.count, worse(heap[left], heap[worst]) { worst = left }
                    if right < heap.count, worse(heap[right], heap[worst]) { worst = right }
                    if worst == parent { break }
                    heap.swapAt(parent, worst)
                    parent = worst
                }
            }
        }
        heap.sort { worse($1, $0) }   // 权重降序、码升序、词升序
        var seen = Set<String>()
        var out: [PracticeQuestion] = []
        for row in heap where seen.insert(row.text).inserted {
            out.append(PracticeQuestion(kind: .phrase, char: row.text, code: row.code,
                                        roots: phraseParts(word: row.text, code: row.code), recognition: nil))
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

    /// 进度文件跟随 `LAMPYRIS_SUPPORT_DIR`（ADR-215/340）：私有根验收不得写用户真实目录。
    static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupport: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
    ) -> URL {
        let base = ImePaths.supportDirectory(environment: environment, applicationSupport: applicationSupport)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lampyris", isDirectory: true)
        return base.appendingPathComponent("practice.tsv")
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


/// 薄弱字清单（ADR-335）：混输下靠拼音兜底打出来的单字，说明它的五笔码还没记住。
///
/// **默认不记**（`practice.collect_weak_chars` 关）；只存本机一个有界 TSV，删除即清空；
/// 只用来让「完整码」练习多出这些字，**不参与候选排序、不上报**。
final class WeakChars {
    static let shared = WeakChars(url: defaultURL())
    static let maxRows = 500
    private(set) var rows: [String: (count: Int, lastSeen: Int)] = [:]
    let url: URL

    init(url: URL) {
        self.url = url
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t").map(String.init)
            guard fields.count == 3, fields[0].count == 1, let count = Int(fields[1]), let last = Int(fields[2])
            else { continue }
            rows[fields[0]] = (count, last)
        }
    }

    /// 薄弱字文件同样跟随 `LAMPYRIS_SUPPORT_DIR`（ADR-215/340）。
    static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        applicationSupport: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first
    ) -> URL {
        let base = ImePaths.supportDirectory(environment: environment, applicationSupport: applicationSupport)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Lampyris", isDirectory: true)
        return base.appendingPathComponent("weak-chars.tsv")
    }

    func contains(_ char: String) -> Bool { rows[char] != nil }

    /// 记一次；只收单个汉字。超过上限时丢掉次数最少、最久没出现的。
    func record(_ char: String, now: Int = Int(Date().timeIntervalSince1970)) {
        guard char.count == 1, char.unicodeScalars.allSatisfy({ $0.value >= 0x3400 }) else { return }
        rows[char] = ((rows[char]?.count ?? 0) + 1, now)
        if rows.count > Self.maxRows {
            let drop = rows.sorted { ($0.value.count, $0.value.lastSeen) < ($1.value.count, $1.value.lastSeen) }
                .prefix(rows.count - Self.maxRows)
            for item in drop { rows[item.key] = nil }
        }
        save()
    }

    /// 原子写：先写临时文件再替换；失败保留旧文件。
    private func save() {
        var lines = ["# 萤火虫薄弱字清单 v1：字\t拼音兜底次数\t最近时间（离线，可删除清空）"]
        for (char, row) in rows.sorted(by: { $0.key < $1.key }) {
            lines.append("\(char)\t\(row.count)\t\(row.lastSeen)")
        }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".weak-chars.tsv.\(UUID().uuidString)")
        do {
            try (lines.joined(separator: "\n") + "\n").write(to: temporary, atomically: false, encoding: .utf8)
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    /// 清空并删除文件。
    func reset() {
        rows = [:]
        try? FileManager.default.removeItem(at: url)
    }
}

/// 一局练习的纯逻辑（无 AppKit），便于自动化测试跑通流程。
final class PracticeSession {
    struct Result {
        let correct: Bool
        let explanation: String
    }

    /// 已作答的一条快照（ADR-362）：回看只读这份快照，不再读写 `practice.tsv`。
    struct Entry {
        let question: PracticeQuestion
        /// 用户提交的答案：敲码题为字母串，识别码题为「末笔+结构」。
        let answer: String
        let result: Result
    }

    private(set) var kind: PracticeKind
    private(set) var question: PracticeQuestion?
    private let progress: PracticeProgress
    private(set) var bank: [PracticeQuestion] = []
    /// 本次练习窗口内已作答的题（按作答顺序）；`back()` / `next()` 在其中移动。
    private(set) var history: [Entry] = []
    /// 正在回看 `history` 的下标；`nil` = 停在最新题。
    private(set) var reviewIndex: Int?
    /// 当前显示的题已作答时的记录（刚答完或回看）；`nil` = 还没作答。
    private(set) var currentEntry: Entry?

    /// 是否处于回看状态（当前题不是「最新未作答题」）。
    var isReviewing: Bool { reviewIndex != nil }

    /// 能否回上一题：回看中看前面还有没有；停在最新题时看历史里有没有上一条。
    var canGoBack: Bool {
        if let reviewIndex { return reviewIndex > 0 }
        guard !history.isEmpty else { return false }
        return currentEntry == nil ? true : history.count > 1
    }

    /// 薄弱字清单：「完整码」题型里这些字额外加权（ADR-335）；`nil` = 不用。
    private let weak: WeakChars?
    /// 薄弱字的额外权重：相当于「错过一次」。
    static let weakBonus = 8

    init(kind: PracticeKind, progress: PracticeProgress, weak: WeakChars? = nil) {
        self.kind = kind
        self.progress = progress
        self.weak = weak
        reload()
    }

    func switchKind(_ kind: PracticeKind) {
        self.kind = kind
        reload()
    }

    func reload() {
        bank = Practice.bank(kind: kind)
        question = nil
        history.removeAll()
        reviewIndex = nil
        currentEntry = nil
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

    /// 下一题：回看中先往后翻历史，翻到最后一条后再抽新题（ADR-362）。
    /// `pick` 仅供测试注入（参数为总权重，返回 `0..<总权重`）。
    @discardableResult
    func next(pick: (Int) -> Int = { Int.random(in: 0..<$0) }) -> PracticeQuestion? {
        if let index = reviewIndex {
            if index + 1 < history.count {
                show(history[index + 1], review: index + 1)
                return question
            }
            reviewIndex = nil
        }
        currentEntry = nil
        question = pickNext(pick: pick)
        return question
    }

    /// 回上一题：停在最新题时回最近一条作答；回看中再往前退一条。到头返回 `false`。
    @discardableResult
    func back() -> Bool {
        if let index = reviewIndex {
            guard index > 0 else { return false }
            show(history[index - 1], review: index - 1)
            return true
        }
        guard !history.isEmpty else { return false }
        let target = currentEntry == nil ? history.count - 1 : history.count - 2
        guard target >= 0 else { return false }
        show(history[target], review: target)
        return true
    }

    private func show(_ entry: Entry, review index: Int) {
        reviewIndex = index
        currentEntry = entry
        question = entry.question
    }

    /// 按权重抽下一题；题库多于一题时不连出同一个字。
    private func pickNext(pick: (Int) -> Int) -> PracticeQuestion? {
        let previous = question?.char
        let pool = bank.count > 1 ? bank.filter { $0.char != previous } : bank
        let weights = pool.map { question -> Int in
            let bonus = kind == .code && weak?.contains(question.char) == true ? Self.weakBonus : 0
            return Self.weight(for: progress.row(char: question.char, kind: kind)) + bonus
        }
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

    /// 提交打字答案；`nil` 表示没有题目或这一题已经答过（ADR-362：答题只记一次）。
    func submitCode(_ answer: String) -> Result? {
        guard let question, reviewIndex == nil, currentEntry == nil else { return nil }
        let correct = Practice.judgeCode(answer, question: question)
        progress.record(char: question.char, kind: kind, correct: correct)
        // 码值统一在答案区展示，这里只回对错，避免同一信息出现两次。
        let result = Result(correct: correct, explanation: "")
        record(Entry(question: question, answer: answer, result: result))
        return result
    }

    /// 提交识别码选择；证据说明用**正确**的末笔与结构，而不是用户选的。
    func submitRecognition(stroke: String, structure: String) -> Result? {
        guard let question, question.recognition != nil, reviewIndex == nil, currentEntry == nil else {
            return nil
        }
        let correct = Practice.judgeRecognition(stroke: stroke, structure: structure, question: question)
        progress.record(char: question.char, kind: kind, correct: correct)
        let result = Result(correct: correct, explanation: "")
        record(Entry(question: question, answer: "\(stroke)+\(structure)", result: result))
        return result
    }

    /// 答错后重试（ADR-366）：只清"当前题已作答"指针，历史里这次错答保留、进度不回收，
    /// 用户可以重新作答；答对后 `retry()` 不再生效。
    @discardableResult
    func retry() -> Bool {
        guard reviewIndex == nil, let entry = currentEntry, !entry.result.correct else { return false }
        currentEntry = nil
        return true
    }

    private func record(_ entry: Entry) {
        currentEntry = entry
        history.append(entry)
    }

    var summary: String { progress.summary }
}
