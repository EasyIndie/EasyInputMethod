// 给「安装 / 卸载 / 更新」三个辅助程序生成「同一只萤火虫 + 角色角标」的图标母版。
//
// 为什么需要它（ADR-390）：四个 app 以前共用同一张 AppIcon，Finder 里只看得到四个
// 一模一样的小绿块，用户分不出哪个是安装器；而且旧母版自带白边，macOS 26 会把旧式
// 图标放进白色托板，视觉上又多一圈白。
//
// 用法：swift tools/render-role-icon.swift <base.png> <out.png> <badge-symbol>
import AppKit

private let side = 1024
private let plate = NSColor(srgbRed: 0.96, green: 0.95, blue: 0.89, alpha: 1)
private let ink = NSColor(srgbRed: 0.12, green: 0.28, blue: 0.25, alpha: 1)

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 4 else {
    FileHandle.standardError.write(Data("用法：render-role-icon.swift <base.png> <out.png> <symbol>\n".utf8))
    exit(2)
}
let baseURL = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])
let symbolName = arguments[3]
guard let base = NSImage(contentsOf: baseURL) else { fail("无法读取底图：\(baseURL.path)") }
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fail("无法创建绘图上下文") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
base.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero,
          operation: .copy, fraction: 1)

// 角标放在右下角，避开 macOS 的圆形/圆角遮罩在正方形的裁切。
let center = NSPoint(x: Double(side) * 0.775, y: Double(side) * 0.225)
let radius = Double(side) * 0.175
ink.setFill()
NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)).fill()
plate.setFill()
let inner = radius * 0.9
NSBezierPath(ovalIn: NSRect(x: center.x - inner, y: center.y - inner,
                            width: inner * 2, height: inner * 2)).fill()

let configuration = NSImage.SymbolConfiguration(pointSize: radius * 1.15, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
    .withSymbolConfiguration(configuration) {
    let height = radius * 1.15
    let width = height * (symbol.size.width / max(symbol.size.height, 1))
    symbol.draw(in: NSRect(x: center.x - width / 2, y: center.y - height / 2,
                           width: width, height: height))
} else {
    fail("找不到系统符号：\(symbolName)（需要 macOS 11+ 的 SF Symbols）")
}
NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else { fail("无法编码 PNG") }
do { try data.write(to: outputURL) } catch { fail("无法写入：\(outputURL.path)") }
print(outputURL.path)
