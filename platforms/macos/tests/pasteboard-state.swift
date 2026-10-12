import AppKit
import Foundation

struct Snapshot: Codable {
    let items: [[String: Data]]
}

enum StateError: Error { case unavailable, changed, writeFailed }

func capture(_ board: NSPasteboard) throws -> Snapshot {
    let before = board.changeCount
    var items: [[String: Data]] = []
    for item in board.pasteboardItems ?? [] {
        var data: [String: Data] = [:]
        for type in item.types {
            guard let value = item.data(forType: type) else { throw StateError.unavailable }
            data[type.rawValue] = value
        }
        items.append(data)
    }
    guard before == board.changeCount else { throw StateError.changed }
    return Snapshot(items: items)
}

func restore(_ snapshot: Snapshot, to board: NSPasteboard, expected: Int) throws {
    guard board.changeCount == expected else { throw StateError.changed }
    let items = snapshot.items.map { values -> NSPasteboardItem in
        let item = NSPasteboardItem()
        for (type, data) in values { item.setData(data, forType: NSPasteboard.PasteboardType(type)) }
        return item
    }
    board.clearContents()
    if !items.isEmpty && !board.writeObjects(items) { throw StateError.writeFailed }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    guard let command = args.first else { throw StateError.unavailable }
    let board = NSPasteboard.general
    switch command {
    case "count": print(board.changeCount)
    case "save":
        guard args.count == 2 else { throw StateError.unavailable }
        let savedCount = board.changeCount
        let value = try capture(board)
        let data = try JSONEncoder().encode(value)
        guard FileManager.default.createFile(atPath: args[1], contents: data,
                                            attributes: [.posixPermissions: 0o600]) else {
            throw StateError.writeFailed
        }
        guard savedCount == board.changeCount else { throw StateError.changed }
        print(savedCount)
    case "restore":
        guard args.count == 3, let expected = Int(args[2]) else { throw StateError.unavailable }
        let value = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        try restore(value, to: board, expected: expected)
    case "self-test":
        let test = NSPasteboard(name: NSPasteboard.Name("Lampyris-test-\(UUID().uuidString)"))
        defer { test.releaseGlobally() }
        let original = Snapshot(items: [["public.utf8-plain-text": Data("测试".utf8),
                                         "cn.lampyris.test.binary": Data([0, 255, 10])],
                                        ["public.utf8-plain-text": Data("second".utf8)]])
        try restore(original, to: test, expected: test.changeCount)
        let encoded = try JSONEncoder().encode(capture(test))
        let saved = try JSONDecoder().decode(Snapshot.self, from: encoded)
        test.clearContents()
        try restore(saved, to: test, expected: test.changeCount)
        guard try capture(test).items == original.items else { throw StateError.writeFailed }
        let stale = test.changeCount
        test.clearContents()
        test.setString("用户新内容", forType: .string)
        do {
            try restore(saved, to: test, expected: stale)
            throw StateError.writeFailed
        } catch StateError.changed {}
        guard test.string(forType: .string) == "用户新内容" else { throw StateError.writeFailed }
        try restore(Snapshot(items: []), to: test, expected: test.changeCount)
        guard try capture(test).items.isEmpty else { throw StateError.writeFailed }
        print("PASS 多项目/多类型/二进制往返、并发保护及空剪贴板")
    default: throw StateError.unavailable
    }
} catch {
    fputs("BLOCKED 剪贴板状态操作失败：\(error)\n", stderr)
    exit(3)
}
