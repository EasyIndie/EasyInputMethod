import Foundation

/// 五笔连续单字自动造词（ADR-341，默认关闭）。
///
/// 只观察**纯五笔模式**下连续上屏的单字：同一串 2–4 个字、相邻上屏间隔 ≤2 秒，
/// 出现 3 次后把整串词交给用户词库。规则刻意保守：
/// - 只看当前焦点会话；失焦、切模式、切中英都会把「当前串」清空（累计次数保留，且有上限）。
/// - 上屏标点、词组或任何多字文本都会打断当前串。
/// - 不在热路径做查表：只有达到阈值的那一次才推导词组码。
struct AutoPhraseRule {
    static let window: TimeInterval = 2
    static let maxRun = 4
    static let threshold = 3
    static let maxTracked = 32

    private var run: [String] = []
    private var last = Date.distantPast
    private var counts: [String: Int] = [:]
    private var order: [String] = []

    /// 记录一次上屏；达到阈值时返回应当写入用户词库的词。
    mutating func record(_ text: String, at now: Date) -> String? {
        guard text.count == 1, let scalar = text.unicodeScalars.first,
              (0x4E00...0x9FFF).contains(scalar.value)
        else {
            reset()
            return nil
        }
        if now.timeIntervalSince(last) <= Self.window, run.count < Self.maxRun {
            run.append(text)
        } else {
            run = [text]
        }
        last = now
        guard run.count >= 2 else { return nil }
        let word = run.joined()
        if counts[word] == nil {
            order.append(word)
            if order.count > Self.maxTracked {
                counts.removeValue(forKey: order.removeFirst())
            }
        }
        counts[word, default: 0] += 1
        guard counts[word, default: 0] >= Self.threshold else { return nil }
        counts[word] = 0
        return word
    }

    /// 打断当前串（累计次数保留）。
    mutating func reset() {
        run = []
        last = .distantPast
    }

    /// 词组取码：两字各取前两码；三字前两字取首码、末字取前两码；四字各取首码。
    /// 任一字的完整码缺失或长度不够时返回 `nil`（不造半截词）。
    static func phraseCode(_ word: String) -> String? {
        let chars = word.map(String.init)
        let spans: [Int]
        switch chars.count {
        case 2: spans = [2, 2]
        case 3: spans = [1, 1, 2]
        case 4: spans = [1, 1, 1, 1]
        default: return nil
        }
        var code = ""
        for (char, span) in zip(chars, spans) {
            guard let full = LearningHints.hint(for: char)?.code, full.count >= span else {
                return nil
            }
            code += String(full.prefix(span))
        }
        return code.count == 4 ? code.lowercased() : nil
    }
}
