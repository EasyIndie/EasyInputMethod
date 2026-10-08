import ime

// 验证：头文件 + module.modulemap 可被 Swift `import ime` 使用（typecheck 即可，不链接）。
let session: OpaquePointer? = ime_session_new()
if let session {
    _ = ime_session_key(session, UInt32(0x77)) // 'w'
    _ = ime_session_key(session, UInt32(0x71)) // 'q'

    let candidates = ime_session_candidates(session)
    if candidates.len > 0 {
        _ = ime_session_select(session, 0)
        let committed = ime_session_commit(session)
        if let data = committed.data {
            print("commit: \(String(cString: data))")
        }
        ime_string_free(committed)
    }

    ime_session_free(session)
}

if let mode = ime_config_get("mode") {
    print("mode: \(String(cString: mode))")
}

let schema = ime_config_schema()
if let schema {
    print("schema options: \(schema.pointee.len)")
}
