// 萤火虫输入法 · 宿主 FFI 运行时冒烟（真实数据文件）
//
// 验证：swiftc 链接 staticlib → 从 TSV 加载真实数据 → 五笔 `wq`→「你」、
// 拼音 `nihao`→「你好」。不涉及 IMK，仅验证引擎 + FFI。
//
// 用法（见 run-ffi-smoke.sh）：ffi_smoke <wubi.tsv> <pinyin-chars.tsv> <pinyin-core.tsv>

import Foundation
import ime

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("❌ " + message + "\n").utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 4 else {
    fail("用法：ffi_smoke <wubi.tsv> <pinyin-chars.tsv> <pinyin-core.tsv>")
}
let (wubiPath, charsPath, wordsPath) = (args[1], args[2], args[3])

guard let session = ime_session_new_with_data(wubiPath, charsPath, wordsPath) else {
    fail("ime_session_new_with_data 返回 NULL")
}
defer { ime_session_free(session) }

func feed(_ text: String) {
    for scalar in text.unicodeScalars {
        _ = ime_session_key(session, scalar.value)
    }
}

func firstCandidate() -> String? {
    let list = ime_session_candidates(session)
    guard list.len > 0, let items = list.items, let ptr = items[0].text else { return nil }
    return String(cString: ptr)
}

// 五笔：wq → 你
feed("wq")
let wubiFirst = firstCandidate()
guard wubiFirst == "你" else { fail("wq 首选应为「你」，实际：\(wubiFirst ?? "nil")") }
guard ime_session_select(session, 0) == IME_OK else { fail("选择候选失败") }
let committed = ime_session_commit(session)
defer { ime_string_free(committed) }
guard let committedPtr = committed.data, String(cString: committedPtr) == "你" else {
    fail("上屏应为「你」")
}

// 拼音：nihao → 你好
_ = "pinyin".withCString { ime_session_set_mode(session, $0) }
feed("nihao")
let pinyinFirst = firstCandidate()
guard pinyinFirst == "你好" else { fail("nihao 首选应为「你好」，实际：\(pinyinFirst ?? "nil")") }

print("✅ FFI 运行时冒烟通过：wq→你，nihao→你好")
