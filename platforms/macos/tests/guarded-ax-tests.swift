import Foundation

func require(_ value: Bool, _ message: String) {
    guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
final class Fake: PressBackend {
    typealias Element = Int
    var calls: [String] = []
    var contexts = [["focus": "owned", "source": "test", "host": "100"]]
    var targets: [PressTarget] = []
    var failAt = ""
    var count = 0
    var identityCount = 0
    func context() throws -> [String: String] {
        calls.append("context")
        if failAt == "context" { throw GuardFailure("blocked") }
        defer { count += 1 }
        return contexts[min(count, contexts.count - 1)]
    }
    func resolve(_ target: PressTarget) throws -> Int {
        calls.append("resolve")
        if failAt == "resolve" { throw GuardFailure("missing") }
        return 1
    }
    func identity(_ element: Int) throws -> PressTarget {
        calls.append("identity")
        defer { identityCount += 1 }
        return targets[min(identityCount, targets.count - 1)]
    }
    func press(_ element: Int) throws {
        calls.append("press")
        if failAt == "press" { throw GuardFailure("AX failure") }
    }
}
let target = PressTarget(windowIndex: 0, childPath: [1, 2], windowTitle: "", windowFrame: "owned", label: "逐字拆分")
let other = PressTarget(windowIndex: 0, childPath: [1, 2], windowTitle: "", windowFrame: "changed", label: "逐字拆分")
var scenarios = 0
func test(_ name: String, configure: (Fake) -> Void, expected: [String], pass: Bool = false) {
    let fake = Fake()
    fake.targets = [target]
    configure(fake)
    do { try guardedPress(fake, target: target); require(pass, name + " should block") }
    catch { require(!pass, name + " should execute") }
    require(fake.calls == expected, name + " call order/no retry")
    scenarios += 1
}
test("success", configure: { _ in }, expected: ["context", "resolve", "identity", "context", "identity", "press"], pass: true)
test("initial context fails", configure: { $0.failAt = "context" }, expected: ["context"])
test("missing target", configure: { $0.failAt = "resolve" }, expected: ["context", "resolve"])
test("wrong target", configure: { $0.targets = [other] }, expected: ["context", "resolve", "identity"])
for key in ["focus", "source", "host"] {
    test("changed " + key, configure: { fake in var changed = fake.contexts[0]; changed[key] = "changed"; fake.contexts.append(changed) }, expected: ["context", "resolve", "identity", "context"])
}
test("target replaced", configure: { $0.targets = [target, other] }, expected: ["context", "resolve", "identity", "context", "identity"])
test("AX fails no retry", configure: { $0.failAt = "press" }, expected: ["context", "resolve", "identity", "context", "identity", "press"])
// Native adapter must reject this account before querying GUI/AX or taking an action.
let process = ProcessBinding(pid: 1, executable: "/invalid", sha256: String(repeating: "0", count: 64), launchedAt: 0)
let sameAccount = GuardedPressPlan(operatorUID: getuid(), testUID: getuid(), home: NSHomeDirectory(), sourceID: "invalid", runDirectory: "/invalid", fixture: "/invalid", fixtureTitle: "invalid", client: process, host: process, target: target)
do { try guardedPress(NativePressBackend(sameAccount), target: target); require(false, "native same account must block") }
catch { require(String(describing: error).contains("独立账号"), "block before GUI queries") }
scenarios += 1
print("PASS guarded-ax \(scenarios) scenarios; synthetic actions only; native same-account rejection")
