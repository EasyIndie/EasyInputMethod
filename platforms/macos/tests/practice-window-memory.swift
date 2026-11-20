// 练习窗口生命周期回归（P1-M2 / 报告 330）。
//
// 1.3.3 真机实测：宿主冷启动 38.8 MiB → 开练习 55.7 → 关窗 **55.8**（一分不收）。
// 原因有两层：
//   1. `PracticeWindow.shared` 只建一次窗口，`isReleasedWhenClosed = false`，关窗 = orderOut，
//      控件树 / 图层 / 键位图面板全留在进程里；
//   2. 即使按关窗拆卸，`phys_footprint` 也**不会**立刻回落——AppKit 的 AttributeGraph、
//      CJK 字形与文本布局缓存是进程级常驻（实测见报告 330 的区域表）。
//
// 所以这里钉的是**状态**而不是数字（ADR-385 的教训）：
//   A. 开窗默认不构造键位图面板（约 7 MiB，默认隐藏）；
//   B. 关窗后窗口与面板都必须被释放；
//   C. 反复开/关不再增长（第二轮起每次 < 1.5 MiB）。
// 具体 MiB 会打印出来供报告引用，但不作为跨机器门禁。
import Cocoa
import Darwin
import ime

func require(_ condition: Bool, _ name: String) {
    if !condition {
        FileHandle.standardError.write(Data(("FAIL: " + name + "\n").utf8))
        exit(1)
    }
}

func footprintBytes() -> Int {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(getpid(), RUSAGE_INFO_V4, $0)
        }
    }
    return result == 0 ? Int(info.ri_phys_footprint) : -1
}

/// 跑一小段 run loop 再量：AppKit 的图层提交与延迟释放都在下一轮才发生，
/// 不转 run loop 时"关窗"看着像没反应（报告 330 §3 的教训）。
func settledFootprint() -> Int {
    RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    return footprintBytes()
}

func mib(_ bytes: Int) -> Double { Double(bytes) / (1024 * 1024) }
func fmt(_ bytes: Int) -> String { String(format: "%.2f", mib(bytes)) }

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: probe <work-dir>\n".utf8))
    exit(2)
}
let workDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
_ = NSApplication.shared
// 测试进程不开前台、不抢焦点：只建窗口、只绘制，不 orderFront。
NSApp.setActivationPolicy(.prohibited)

let progressURL = workDir.appendingPathComponent("practice.tsv")
let practice = PracticeWindow.shared

let cold = settledFootprint()
require(practice.windowForTesting == nil, "进程起步时不应已建练习窗口")

// 第一轮：开（不碰键位图）→ 关
var openedNoKeymap = 0
var openedWithKeymap = 0
autoreleasepool {
    practice.prepareForTesting(progressURL: progressURL)
    openedNoKeymap = settledFootprint()
    require(practice.windowForTesting != nil, "prepareForTesting 之后应当有窗口")
    require(!practice.keymapPanelBuiltForTesting, "默认不应构造键位图面板（它默认是隐藏的）")
    practice.setKeymapVisibleForTesting(true)
    openedWithKeymap = settledFootprint()
    require(practice.keymapPanelBuiltForTesting, "点开「键位图」后才构造面板")
    // 关窗即拆意味着下次开窗要重建视图：版式必须还是对的（越界/重叠＝重建路径坏了）。
    let problems = practice.layoutProblemsForTesting(kind: .code)
    require(problems.isEmpty, "重建的内容视图版式应正常：\(problems)")
    practice.setKeymapVisibleForTesting(false)
    practice.closeForTesting()
}
let closed = settledFootprint()
require(practice.windowForTesting == nil, "关窗后窗口对象必须被释放（windowWillClose → dismantle）")
require(!practice.keymapPanelBuiltForTesting, "关窗后键位图面板也必须被释放")

// 第二轮起：反复开/关只应付出重建视图的零头，不能逐次增长
var cycles: [Int] = []
for _ in 0..<4 {
    autoreleasepool {
        practice.prepareForTesting(progressURL: progressURL)
        practice.closeForTesting()
    }
    cycles.append(settledFootprint())
    require(practice.windowForTesting == nil, "每轮关窗后窗口都必须被释放")
}

let keymapCost = mib(openedWithKeymap - openedNoKeymap)
let openCost = mib(openedNoKeymap - cold)
let reopenCosts = cycles.map { mib($0 - closed) }
let drift = mib(cycles.last! - closed)

FileHandle.standardError.write(Data("""
practice-window-memory: cold=\(fmt(cold)) open=\(fmt(openedNoKeymap)) \
open+keymap=\(fmt(openedWithKeymap)) closed=\(fmt(closed)) \
open=\(String(format: "%.2f", openCost))MiB keymap=\(String(format: "%.2f", keymapCost))MiB \
drift=\(String(format: "%.2f", drift))MiB cycles=[\(reopenCosts.map { String(format: "%.2f", $0) }.joined(separator: ", "))]

""".utf8))

// A：键位图是默认隐藏的大件，不该在开窗时就付钱
require(keymapCost > 1, "键位图面板应确实占几 MiB，实测 \(String(format: "%.2f", keymapCost)) MiB")
// B：反复开关不增长（重建视图的零头 < 1.5 MiB/轮，总量 < 2 MiB）
require(drift < 2,
        "反复开/关不应逐次增长：\(String(format: "%.2f", drift)) MiB（各轮 \(reopenCosts.map { String(format: "%.2f", $0) })）")

print("PASS practice-window-memory open=\(String(format: "%.2f", openCost)) keymap=\(String(format: "%.2f", keymapCost)) drift=\(String(format: "%.2f", drift))")
