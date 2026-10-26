// 显示模式探针：列出/切换某块屏幕的分辨率模式，供「缩放」验收（报告202）。
// 用法：displaymode list | current <index> | set <index> <width> x <height> | restore <index> <width>x<height>
// 只切换 display mode，不改任何系统设置文件；用完必须 restore 回原模式。
import AppKit
import CoreGraphics

func displayID(for index: Int) -> CGDirectDisplayID? {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
    var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
    return index < displays.count ? displays[index] : nil
}

func describe(_ mode: CGDisplayMode) -> String {
    let pointWidth = mode.pixelWidth / max(1, Int(mode.pixelWidth / max(1, mode.width)))
    return "\(mode.width)x\(mode.height)@\(mode.refreshRate)Hz pixel=\(mode.pixelWidth)x\(mode.pixelHeight) point=\(pointWidth)"
}

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : "list"

switch command {
case "list":
    var index = 0
    var output: [String] = []
    while let id = displayID(for: index) {
        let current = CGDisplayCopyDisplayMode(id)
        output.append("display \(index) id=\(id) bounds=\(CGDisplayBounds(id).width)x\(CGDisplayBounds(id).height) current=\(current.map(describe) ?? "?")")
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        for mode in (CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode]) ?? [] where mode.width > 0 {
            output.append("  mode \(mode.width)x\(mode.height)@\(mode.refreshRate)Hz pixel=\(mode.pixelWidth)x\(mode.pixelHeight)")
        }
        index += 1
    }
    print(output.joined(separator: "\n"))
case "set", "restore":
    guard args.count >= 4, let index = Int(args[2]) else { print("usage: displaymode set <index> <width>x<height>"); exit(2) }
    let parts = args[3].split(separator: "x").compactMap { Int($0) }
    guard parts.count == 2, let id = displayID(for: index) else { print("BAD_ARGS"); exit(2) }
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode] else { print("NO_MODES"); exit(1) }
    // 同尺寸可能有 HiDPI 与 1x 两个模式：优先 HiDPI（pixelWidth 更大），否则缩放会把 Retina 变成 1x（报告202）。
    let matching = all.filter { $0.width == parts[0] && $0.height == parts[1] }
    guard let target = matching.max(by: { $0.pixelWidth < $1.pixelWidth }) else {
        print("MODE_NOT_FOUND \(args[3])")
        exit(1)
    }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success else { print("CONFIG_FAILED"); exit(1) }
    CGConfigureDisplayWithDisplayMode(config, id, target, nil)
    let status = CGCompleteDisplayConfiguration(config, .forSession)
    print("\(command) display \(index) \(parts[0])x\(parts[1]) status=\(status.rawValue)")
    exit(status == .success ? 0 : 1)
default:
    print("usage: displaymode list | set <index> <width>x<height>")
    exit(2)
}
