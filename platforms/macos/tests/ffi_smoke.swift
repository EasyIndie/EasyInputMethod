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

// Keep all learning/configuration IO inside a new private test directory.
let learningRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("lampyris-learning-smoke-" + UUID().uuidString)
do { try FileManager.default.createDirectory(at: learningRoot, withIntermediateDirectories: true) }
catch { fail("无法创建隔离学习目录") }
defer { try? FileManager.default.removeItem(at: learningRoot) }
guard ime_config_init(learningRoot.appendingPathComponent("config.toml").path) == IME_OK else {
    fail("隔离配置初始化失败")
}

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

// Mixed ambiguity must remain selectable with the shipped default tables.
_ = "mixed".withCString { ime_session_set_mode(session, $0) }
guard ime_session_configure(session) == IME_OK else { fail("隔离混输配置失败") }
for scalar in "wang".unicodeScalars {
    guard ime_session_key(session, scalar.value) == 0 else { fail("混输wang不得提前上屏") }
}
let mixedChoices = ime_session_candidates(session)
guard mixedChoices.len >= 2, let choices = mixedChoices.items,
      let first = choices[0].text, let second = choices[1].text,
      String(cString: first) == "佢", String(cString: second) == "王" else {
    fail("混输wang应保留佢及王")
}
guard ime_session_key(session, 50) == 1 else { fail("混输数字2应提交王") }
let mixedCommit = ime_session_commit(session)
guard let value = mixedCommit.data, String(cString: value) == "王" else { fail("混输提交目标错误") }
ime_string_free(mixedCommit)
print("✅ 混输歧义保护通过：wang保留候选，数字2→王")

// Exercise the actual Swift/C ABI learning path with synthetic private fixtures.
let learningTable = learningRoot.appendingPathComponent("table.tsv")
let learningSeed = learningRoot.appendingPathComponent("seed.tsv")
do {
    try "ab\t历史首项\t100\nab\t常选后项\t1\n".write(to: learningTable, atomically: true, encoding: .utf8)
    try "wubi\tab\t历史首项\t1000\n".write(to: learningSeed, atomically: true, encoding: .utf8)
} catch { fail("无法写入隔离学习样例") }
func learningSession() -> OpaquePointer {
    guard let s = ime_session_new_with_data(learningTable.path, charsPath, wordsPath) else {
        fail("无法创建隔离学习会话")
    }
    guard ime_session_configure(s) == IME_OK else { fail("隔离学习配置失败") }
    return s
}
func learningFirst(_ s: OpaquePointer) -> String? {
    let list = ime_session_candidates(s)
    guard list.len > 0, let items = list.items, let value = items[0].text else { return nil }
    return String(cString: value)
}
let learner = learningSession()
guard ime_session_dictionary_import(learner, learningSeed.path) == IME_OK else { fail("学习样例导入失败") }
for _ in 0..<4 {
    _ = ime_session_key(learner, 97)
    _ = ime_session_key(learner, 98)
    guard learningFirst(learner) == "历史首项" else { fail("学习前排序异常") }
    guard ime_session_key(learner, 50) == IME_KEY_COMMITTED else { fail("主动选择未提交") }
    guard ime_session_dictionary_error(learner) == IME_OK else { fail("隔离学习持久化失败") }
}
ime_session_free(learner)
let learned = learningSession()
defer { ime_session_free(learned) }
_ = ime_session_key(learned, 97)
_ = ime_session_key(learned, 98)
guard learningFirst(learned) == "常选后项" else { fail("重新加载后主动学习未生效") }
print("✅ Swift/C ABI 离线学习通过：历史1000后四次主动选择前移，重载保留；仅临时词库")
