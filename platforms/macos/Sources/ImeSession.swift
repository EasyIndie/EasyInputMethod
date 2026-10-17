// 会话 FFI 的 Swift 封装。
//
// 只做「指针 <> Swift 类型」的转换，不承载任何引擎逻辑（业务全在 Rust 侧）。
// 线程绑定：一个 ImeSession 只在主线程使用（IMK 控制器回调都在主线程）。

import Cocoa
import ime

/// 候选来源（对应 C 头 `IME_SOURCE_*`）。
enum CandidateSource: Int32 {
    case codeTable = 0
    case pinyin = 1
    case phrase = 2

    /// 混输来源标签（中文）。
    var label: String {
        switch self {
        case .codeTable: return "五笔"
        case .pinyin: return "拼"
        case .phrase: return "词"
        }
    }
}

/// 单个候选。
struct ImeCandidate {
    let text: String
    let code: String
    let source: CandidateSource
    let isPrefix: Bool
}

/// Read-only, bounded teaching data supplied by the Rust model.
struct WubiLearning {
    struct Root { let text: String; let key: String }
    struct Character {
        let text: String
        let code: String?
        let category: String?
        let rule: String?
        let roots: [Root]
        let recognition: Root?
    }
    let code: String?
    let rule: String
    let characters: [Character]

    static func lookup(_ text: String) -> WubiLearning? {
        let value = text.withCString { ime_wubi_learning($0) }
        defer { ime_string_free(value) }
        guard let pointer = value.data, value.len > 0, value.len <= 65536 else { return nil }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(value.len))
        guard let payload = String(bytes: bytes, encoding: .utf8) else { return nil }
        let lines = payload.components(separatedBy: "\n")
        let header = lines[0].components(separatedBy: "\t")
        guard header.count == 3, header[0] == "wubi-learning-v1", lines.count <= 257 else { return nil }
        func optional(_ value: String) -> String? { value.isEmpty ? nil : value }
        func pair(_ value: String) -> Root? {
            let fields = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard fields.count == 2, !fields[0].isEmpty, fields[1].count == 1,
                  let key = fields[1].utf8.first, (97...121).contains(key) else { return nil }
            return Root(text: String(fields[0]), key: String(fields[1]).uppercased())
        }
        var characters: [Character] = []
        for line in lines.dropFirst() {
            let fields = line.components(separatedBy: "\t")
            guard fields.count == 6, fields[0].count == 1 else { return nil }
            let encodedRoots = fields[4].split(separator: " ").map(String.init)
            let roots = encodedRoots.compactMap(pair)
            guard roots.count == encodedRoots.count else { return nil }
            let recognition = pair(fields[5])
            guard fields[5].isEmpty || recognition != nil else { return nil }
            characters.append(Character(text: fields[0], code: optional(fields[1]), category: optional(fields[2]),
                rule: optional(fields[3]), roots: roots, recognition: recognition))
        }
        guard characters.map(\.text).joined() == text else { return nil }
        return WubiLearning(code: optional(header[1]), rule: header[2], characters: characters)
    }
}

/// `ime_session_key` 的结果。
enum ImeKeyResult {
    case consumed
    case committed(String)
    case passThrough
    case failure(Int32)
}

/// A recognized shortcut is consumed even if persistence fails.
enum ShortcutResult {
    case unmatched, handled, failed
    var consumed: Bool { self != .unmatched }
}

/// 不透明会话句柄的封装。
final class ImeSession {
    private var handle: OpaquePointer?

    /// 从真实数据文件创建；加载失败返回 `nil`。
    init?(wubiPath: String, pinyinCharsPath: String?, pinyinWordsPath: String?) {
        let created: OpaquePointer? = wubiPath.withCString { wubi in
            if let chars = pinyinCharsPath {
                return chars.withCString { charsPtr in
                    if let words = pinyinWordsPath {
                        return words.withCString { wordsPtr in
                            ime_session_new_with_data(wubi, charsPtr, wordsPtr)
                        }
                    }
                    return ime_session_new_with_data(wubi, charsPtr, nil)
                }
            }
            return ime_session_new_with_data(wubi, nil, nil)
        }
        guard let created else { return nil }
        self.handle = created
    }

    /// 内置样本引擎（数据文件缺失时的兜底，保证宿主仍可启动）。
    static func sample() -> ImeSession? {
        guard let handle = ime_session_new() else { return nil }
        let session = ImeSession(handle: handle)
        return session
    }

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        if let handle {
            ime_session_free(handle)
        }
    }

    /// 组合缓冲区（预编辑串）；无组合时为空串。
    var buffer: String {
        guard let handle, let ptr = ime_session_buffer(handle) else { return "" }
        return String(cString: ptr)
    }

    var isComposing: Bool { !buffer.isEmpty }

    /// Keep client navigation from editing marked text while the engine owns it.
    func consumesCompositionNavigation(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, isComposing,
            ((123...126).contains(event.keyCode)
                || [115, 117, 119].contains(event.keyCode))
        else { return false }
        return event.modifierFlags.intersection([.command, .control, .option]).isEmpty
    }

    /// 喂入一个 Unicode 码点。
    func feed(_ codepoint: UInt32) -> ImeKeyResult {
        guard let handle else { return .failure(IME_ERR_NULL) }
        _ = ime_session_configure(handle)
        let code = ime_session_key(handle, codepoint)
        switch code {
        case IME_KEY_COMMITTED:
            return .committed(commit())
        case IME_KEY_CONSUMED:
            return .consumed
        case IME_KEY_PASS_THROUGH:
            return .passThrough
        default:
            return .failure(code)
        }
    }

    var variantError: Int32 { ime_session_variant_error(handle) }
    var isTraditional: Bool { ime_session_is_traditional(handle) == 1 }
    var variantErrorMessage: String? {
        guard variantError != IME_OK else { return nil }
        return "繁体转换数据不可用，当前输出简体（错误码：\(variantError)）。请重新安装完整包，或修复资源后先切简体再启用繁体。"
    }
    var dictionaryError: Int32 { ime_session_dictionary_error(handle) }
    var dictionaryOperationError: String? {
        let result = ime_session_dictionary_error_message(handle)
        defer { ime_string_free(result) }
        guard let text = result.data, result.len > 0 else { return nil }
        return String(cString: text)
    }
    func addWord(scheme: String, code: String, text: String) -> Int32 {
        scheme.withCString { a in code.withCString { b in text.withCString { c in
            ime_session_dictionary_add(handle, a, b, c)
        } } }
    }
    func importDictionary(_ path: String) -> Int32 {
        path.withCString { ime_session_dictionary_import(handle, $0) }
    }
    func removeWord(scheme: String, code: String, text: String) -> Int32 {
        scheme.withCString { a in code.withCString { b in text.withCString { c in
            ime_session_dictionary_remove(handle, a, b, c)
        } } }
    }
    func exportDictionary(_ path: String) -> Int32 {
        path.withCString { ime_session_dictionary_export(handle, $0) }
    }

    func prepare() { _ = ime_session_configure(handle) }

    var isEnglish: Bool { ime_session_is_english(handle) == 1 }
    /// 当前是否全角（含 Shift+Space 临时切换）。
    var isFullWidth: Bool { ime_session_is_full_width(handle) == 1 }
    func toggleEnglish() { _ = ime_session_toggle_english(handle) }
    func toggleWidth() { _ = ime_session_configure(handle); _ = ime_session_toggle_width(handle) }

    /// 中英标点切换：翻转 `input.punctuation` 并写回配置（默认 `Ctrl+.`）。
    @discardableResult
    func togglePunctuation() -> Bool {
        let next =
            (ImeConfig.string("input.punctuation") ?? "chinese") == "chinese"
            ? "english" : "chinese"
        guard ImeConfig.setString("input.punctuation", next) else { return false }
        prepare()
        return true
    }

    /// 简/繁切换：翻转 `input.chinese_variant` 并写回配置（默认 `Ctrl+Shift+T`，避开编辑器 `Ctrl+Shift+F`）。
    @discardableResult
    func toggleVariant() -> Bool {
        let next =
            (ImeConfig.string("input.chinese_variant") ?? "simplified") == "simplified"
            ? "traditional" : "simplified"
        guard ImeConfig.setString("input.chinese_variant", next) else { return false }
        prepare()
        return true
    }

    /// 注入简→繁转换表（宿主从包内 Resources 载入）。
    @discardableResult
    func setVariantData(_ path: String) -> Int32 {
        guard let handle else { return IME_ERR_NULL }
        return path.withCString { ime_session_set_variant_data(handle, $0) }
    }

    // 单独 Shift 切换中英（对齐搜狗/微信）：需要 flagsChanged 的按下/抬起。
    private var shiftDown = false
    private var shiftUsedByKey = false

    /// flagsChanged：记录 Shift 状态；仅当本次「按住并抬起 Shift」期间既没有其它键、
    /// 也没有 Ctrl/Option/Command 参与时，才触发中英切换（仅当 `hotkey.toggle_english == "shift"`）。
    ///
    /// `otherModifier` 用于排除 `Ctrl+Shift+M` 这类组合：合成/快速输入时 `keyDown` 可能
    /// 晚于 flagsChanged 到达，仅靠 `markKeyWhileShift()` 会漏判，导致抬起时误切英文。
    @discardableResult
    func shiftTransition(isDown: Bool, otherModifier: Bool = false) -> Bool {
        guard ImeConfig.hotkey("hotkey.toggle_english").kind == 1 else { return false }
        if isDown {
            if !shiftDown {
                shiftDown = true
                shiftUsedByKey = false
            }
            if otherModifier { shiftUsedByKey = true }
            return false
        }
        let solo = shiftDown && !shiftUsedByKey
        shiftDown = false
        shiftUsedByKey = false
        if solo {
            toggleEnglish()
            return true
        }
        return false
    }

    /// 任意非修饰键按下时调用：本次 Shift 不算“单独按”。
    func markKeyWhileShift() {
        if shiftDown { shiftUsedByKey = true }
    }

    /// 判断一个组合键设置是否匹配当前按键（`space` 用物理键码 49 判定）。
    func matches(_ key: String, _ event: NSEvent) -> Bool {
        ImeConfig.hotkey(key).matches(event)
    }

    /// 组合键（均可配）：中英 / 全半角 / 切换模式；`"shift"` 与 `"none"` 不作为组合键。
    func shortcut(_ event: NSEvent, persistMode: Bool) -> ShortcutResult {
        if matches("hotkey.toggle_wubi_learning", event) {
            return ImeConfig.setToml("candidate.show_wubi_learning",
                ImeConfig.bool("candidate.show_wubi_learning") ? "false" : "true") ? .handled : .failed
        }
        if matches("hotkey.toggle_english", event) { toggleEnglish(); return .handled }
        if matches("hotkey.toggle_width", event) { toggleWidth(); return .handled }
        if matches("hotkey.toggle_punctuation", event) {
            return togglePunctuation() ? .handled : .failed
        }
        if matches("hotkey.toggle_variant", event) {
            return toggleVariant() ? .handled : .failed
        }
        guard matches("hotkey.toggle_mode", event)
        else { return .unmatched }
        let order = ["mixed", "wubi", "pinyin"]
        let next = order[((order.firstIndex(of: mode) ?? 0) + 1) % 3]
        if persistMode, !ImeConfig.setString("mode", next) { return .failed }
        setMode(next)
        return .handled
    }

    var mode: String { ["mixed", "wubi", "pinyin"][max(0, min(2, Int(ime_session_mode(handle))))] }
    var pageIndex: Int { Int(ime_session_page_index(handle)) }
    var pageCount: Int { Int(ime_session_page_count(handle)) }
    func setPageSize(_ size: Int) { _ = ime_session_set_page_size(handle, Int32(size)) }
    func page(_ delta: Int) { _ = ime_session_page(handle, Int32(delta)) }

    /// Query the installed pinyin data without changing the session.
    func reverseLookup(_ text: String) -> String? {
        guard let handle else { return nil }
        let result = text.withCString { ime_session_reverse_lookup(handle, $0) }
        defer { ime_string_free(result) }
        guard let data = result.data, result.len > 0 else { return nil }
        return String(cString: data)
    }

    /// 取已上屏文本（无内容返回空串）。
    func commit() -> String {
        guard let handle else { return "" }
        let s = ime_session_commit(handle)
        defer { ime_string_free(s) }
        guard let data = s.data else { return "" }
        return String(cString: data)
    }

    /// 取当前候选（最多 `limit` 个）。
    func candidates(limit: Int) -> [ImeCandidate] {
        guard let handle else { return [] }
        let list = ime_session_candidates(handle)
        guard list.len > 0, let items = list.items else { return [] }
        var out: [ImeCandidate] = []
        let count = min(Int(list.len), limit)
        for i in 0..<count {
            let item = items[i]
            out.append(
                ImeCandidate(
                    text: item.text.map { String(cString: $0) } ?? "",
                    code: item.code.map { String(cString: $0) } ?? "",
                    source: CandidateSource(rawValue: item.source) ?? .codeTable,
                    isPrefix: item.is_prefix != 0
                )
            )
        }
        return out
    }

    /// 选择第 `index` 个候选并上屏；返回上屏文本。
    @discardableResult
    func select(_ index: Int) -> String? {
        guard let handle else { return nil }
        guard ime_session_select(handle, Int32(index)) == IME_OK else { return nil }
        return commit()
    }

    /// 切换输入模式（"mixed" / "wubi" / "pinyin"）。
    func setMode(_ mode: String) {
        guard let handle else { return }
        _ = mode.withCString { ime_session_set_mode(handle, $0) }
    }

    /// 取消当前组合。
    func reset() {
        guard let handle else { return }
        ime_session_reset(handle)
    }

    /// 失焦：取消当前组合。
    func focusOut() {
        guard let handle else { return }
        ime_session_focus_out(handle)
    }
}
