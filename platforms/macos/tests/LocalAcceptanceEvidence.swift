import Foundation

/// Test-only observations; an unset output path leaves the existing tests unchanged.
enum LocalAcceptanceEvidence {
    private static var cases: [[String: Any]] = []

    static func record(_ id: String, expected: String, actual: Any) {
        guard let path = ProcessInfo.processInfo.environment["LAMPYRIS_ACCEPTANCE_OUTPUT"] else { return }
        cases.append(["id": id, "expected": expected, "actual": actual, "status": "PASS",
                      "observed_at": ISO8601DateFormatter().string(from: Date()),
                      "scope": "native-offscreen-components"])
        do {
            let directory = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: ["schema": 1, "cases": cases],
                options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("observations.json"), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("FAIL: cannot persist local observations: \(error)\n".utf8))
            exit(1)
        }
    }
}
