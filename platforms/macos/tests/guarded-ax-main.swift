import Foundation

// Explicit paths only; never discovers, activates or selects a different window.
do {
    guard CommandLine.arguments.count == 3,
          ["--inspect", "--press"].contains(CommandLine.arguments[1]) else {
        throw GuardFailure("用法：--inspect或--press 已绑定计划.json；无自动发现或批量执行模式")
    }
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
    let plan = try JSONDecoder().decode(GuardedPressPlan.self, from: data)
    let backend = NativePressBackend(plan)
    if CommandLine.arguments[1] == "--inspect" {
        let before = try backend.context()
        let target = try backend.resolve(plan.target)
        let observed = try backend.identity(target)
        guard try backend.context() == before else { throw GuardFailure("观察期间上下文变化") }
        print(String(decoding: try JSONEncoder().encode(observed), as: UTF8.self))
    } else {
        try guardedPress(backend, target: plan.target)
        print("ACTION_EXECUTED：单次AXPress返回成功；实际行为仍须观察，正式MVP仍待验")
    }
} catch {
    fputs("BLOCKED：\(error)\n", stderr)
    exit(3)
}
