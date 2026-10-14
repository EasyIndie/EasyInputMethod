// Exercise actual host event classification without a window or posted events.
import Cocoa
import ime

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8))
    exit(1)
}
func configurationSnapshot(_ root: URL) -> Data? {
    let path = root.appendingPathComponent("config.toml")
    guard FileManager.default.fileExists(atPath: path.path) else { return nil }
    do { return try Data(contentsOf: path) }
    catch { fail("private configuration snapshot unreadable") }
}
func event(_ key: UInt16, _ flags: NSEvent.ModifierFlags = [],
           _ characters: String = "\u{1f}", _ type: NSEvent.EventType = .keyDown) -> NSEvent {
    guard let result = NSEvent.keyEvent(with: type, location: .zero,
        modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
        characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: key) else { fail("event creation") }
    return result
}
let root = URL(fileURLWithPath: CommandLine.arguments[1])
guard ime_config_init(root.appendingPathComponent("config.toml").path) == IME_OK,
      let session = ImeSession.sample() else { fail("private session") }
let keys: [UInt16] = [115, 119, 117, 123, 124, 125, 126]
for mode in ["wubi", "pinyin", "mixed"] {
    session.setMode(mode)
    for key in keys {
        _ = session.feed(27)
        guard !session.consumesCompositionNavigation(event(key)) else { fail("idle key \(key)") }
        _ = session.feed(119); _ = session.feed(113)
        let candidates = session.candidates(limit: 9).map(\.text)
        for flags: NSEvent.ModifierFlags in [[], .shift, .function, .capsLock, [.shift, .function, .capsLock]] {
            for characters in ["\u{1f}", "\u{f728}", "\u{f729}", "\u{f72b}", ""] {
                guard session.consumesCompositionNavigation(event(key, flags, characters)),
                      session.buffer == "wq", session.candidates(limit: 9).map(\.text) == candidates
                else { fail("unprotected composition key \(key) in \(mode)") }
            }
        }
        for flags: NSEvent.ModifierFlags in [.command, .control, .option, [.command, .shift]] {
            guard !session.consumesCompositionNavigation(event(key, flags)) else { fail("command key \(key)") }
        }
        // Paging and focus traversal are deliberately not classified as editing.
        for other: UInt16 in [116, 121, 48, 57, 13, 51, 53] {
            guard !session.consumesCompositionNavigation(event(other)) else { fail("unrelated key \(other)") }
        }
        _ = session.feed(127)
        guard session.buffer == "w" else { fail("backward delete") }
        _ = session.feed(113)
        if mode == "wubi" {
            if case .committed("你") = session.feed(32) {} else { fail("space commit") }
            _ = session.feed(119); _ = session.feed(113)
            if case .committed("你") = session.feed(49) {} else { fail("digit commit") }
            _ = session.feed(119); _ = session.feed(113)
        }
        _ = session.feed(27)
        guard session.buffer.isEmpty, !session.consumesCompositionNavigation(event(key)) else { fail("cancel") }
        _ = session.feed(119); _ = session.feed(113)
        if case .committed("wq") = session.feed(13) {} else { fail("raw Enter") }
        guard session.buffer.isEmpty else { fail("raw Enter composition") }
    }
}
// Tab remains a client traversal event; test the existing focus-out boundary.
session.setMode("wubi")
_ = session.feed(119); _ = session.feed(113)
if case .passThrough = session.feed(9) {} else { fail("Tab must pass through") }
guard session.buffer == "wq", !session.consumesCompositionNavigation(event(48, [], "\t")),
      !session.consumesCompositionNavigation(event(57, .capsLock, "", .flagsChanged))
else { fail("traversal/modifier classification") }
session.focusOut()
guard session.buffer.isEmpty else { fail("focus-out cancellation") }

// Explicit English must preserve ASCII decimals, paths and email text and
// leave the private dictionary/configuration unchanged.
let before = root.appendingPathComponent("before-english.tsv")
let after = root.appendingPathComponent("after-english.tsv")
guard session.exportDictionary(before.path) == IME_OK else { fail("private export before") }
let configurationBefore = configurationSnapshot(root)
session.toggleEnglish()
guard session.isEnglish else { fail("English state") }
for scalar in "aA 12.34 /tmp/example.txt user@example.test".unicodeScalars {
    if case .passThrough = session.feed(scalar.value) {} else { fail("ASCII English routing") }
    guard session.buffer.isEmpty else { fail("English composition") }
}
guard session.exportDictionary(after.path) == IME_OK else { fail("private export after") }
let dictionaryBefore = try Data(contentsOf: before)
let dictionaryAfter = try Data(contentsOf: after)
let configurationAfter = configurationSnapshot(root)
guard dictionaryBefore == dictionaryAfter, configurationBefore == configurationAfter
else { fail("English must not learn or write preferences") }
print("PASS composition-navigation: 7 keys, 3 modes; idle/composing/cancelled, modifiers, representation, existing commit/edit paths; Tab/focus-out, ASCII English decimals/path/email, no learning/config write")
