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

/// `ime_session_key` 的结果。
enum ImeKeyResult {
    case consumed
    case committed(String)
    case passThrough
    case failure(Int32)
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

    var dictionaryError: Int32 { ime_session_dictionary_error(handle) }
    func addWord(scheme: String, code: String, text: String) -> Int32 {
        scheme.withCString { a in code.withCString { b in text.withCString { c in
            ime_session_dictionary_add(handle, a, b, c)
        } } }
    }
    func importDictionary(_ path: String) -> Int32 {
        path.withCString { ime_session_dictionary_import(handle, $0) }
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

    // 单独 Shift 切换中英（对齐搜狗/微信）：需要 flagsChanged 的按下/抬起。
    private var shiftDown = false
    private var shiftUsedByKey = false

    /// flagsChanged：记录 Shift 状态；抬起且期间无其它键 → 触发中英切换
    /// （仅当 `hotkey.toggle_english == "shift"`）。返回是否触发了切换。
    @discardableResult
    func shiftTransition(isDown: Bool) -> Bool {
        guard ImeConfig.string("hotkey.toggle_english") == "shift" else { return false }
        if isDown {
            shiftDown = true
            shiftUsedByKey = false
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
    private func matches(_ setting: String?, _ event: NSEvent) -> Bool {
        guard let setting, setting != "shift", setting != "none" else { return false }
        let parts = setting.lowercased().split(separator: "+").map(String.init)
        guard let last = parts.last else { return false }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        var expected: NSEvent.ModifierFlags = []
        for modifier in parts.dropLast() {
            switch modifier {
            case "ctrl": expected.insert(.control)
            case "shift": expected.insert(.shift)
            case "alt": expected.insert(.option)
            case "cmd": expected.insert(.command)
            default: return false
            }
        }
        guard flags == expected else { return false }
        if last == "space" {
            return event.keyCode == 49 || event.charactersIgnoringModifiers == " "
        }
        return event.charactersIgnoringModifiers?.lowercased() == last
    }

    /// 组合键（均可配）：中英 / 全半角 / 切换模式；`"shift"` 与 `"none"` 不作为组合键。
    func shortcut(_ event: NSEvent, persistMode: Bool) -> Bool {
        if matches(ImeConfig.string("hotkey.toggle_english"), event) { toggleEnglish(); return true }
        if matches(ImeConfig.string("hotkey.toggle_width"), event) { toggleWidth(); return true }
        guard let configured = ImeConfig.string("hotkey.toggle_mode"), matches(configured, event)
        else { return false }
        let order = ["mixed", "wubi", "pinyin"]
        let next = order[((order.firstIndex(of: mode) ?? 0) + 1) % 3]
        if persistMode, !ImeConfig.setString("mode", next) { return false }
        setMode(next)
        return true
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
