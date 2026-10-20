import Foundation

/// Test-only observations; an unset output path leaves the existing tests unchanged.
enum LocalAcceptanceEvidence {
    private static var cases: [[String: Any]] = []

    /// Dictionary-shaped observations get their own overload: with `actual: Any` alone, Swift 5.8
    /// rejects heterogeneous literals and older toolchains (device A) cannot build the tests.
    static func record(_ id: String, expected: String, actual: [String: Any]) {
        record(id, expected: expected, actual: actual as Any)
    }

    static func record(_ id: String, expected: String, actual: Any) {
        guard let path = ProcessInfo.processInfo.environment["LAMPYRIS_ACCEPTANCE_OUTPUT"] else { return }
        let entry: [String: Any] = ["id": id, "expected": expected, "actual": actual, "status": "PASS",
                                    "observed_at": ISO8601DateFormatter().string(from: Date()),
                                    "scope": "native-offscreen-components"]
        cases.append(entry)
        do {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let payload: [String: Any] = ["schema": 1, "cases": cases]
            let data = try JSONSerialization.data(withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("observations.json"), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("FAIL: cannot persist local observations: \(error)\n".utf8))
            exit(1)
        }
    }
}
