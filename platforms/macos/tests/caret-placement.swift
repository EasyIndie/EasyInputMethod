// CaretPlacement 几何不变量（ADR-301）：纯函数，不需要 AppKit 窗口。
import AppKit

func require(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL caret-placement: \(message)")
        exit(1)
    }
}

let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
let size = NSSize(width: 520, height: 210)

func request(_ caret: NSRect, visible: NSRect = screen, preferBelow: Bool = true,
             align: CaretPlacement.Alignment = .leading, gap: CGFloat = 8) -> CaretPlacement.Request {
    CaretPlacement.Request(caret: caret, panelSize: size, visible: visible,
                           preferBelow: preferBelow, align: align, gap: gap)
}

// 1) 屏幕中部：优先向下，与行框间距恰为 gap。
let middle = NSRect(x: 400, y: 440, width: 1, height: 16)
let belowFrame = CaretPlacement.frame(request(middle))
require(belowFrame.minY == middle.minY - size.height - 8,
        "prefers below with the requested gap: \(belowFrame)")
require(belowFrame.minX == middle.minX, "leading alignment follows the caret: \(belowFrame)")

// 2) 屏幕底部放不下 → 翻到上方。
let bottom = NSRect(x: 400, y: 120, width: 1, height: 16)
let aboveFrame = CaretPlacement.frame(request(bottom))
require(aboveFrame.minY == bottom.maxY + 8, "flips above when there is no room below: \(aboveFrame)")

// 3) 屏幕顶部放不下 → 仍在下方（不能压住正在输入的那一行）。
let top = NSRect(x: 400, y: 860, width: 1, height: 16)
let topFrame = CaretPlacement.frame(request(top))
require(topFrame.maxY <= top.minY - 8 + 0.001,
        "stays below near the top edge instead of covering the caret line: \(topFrame)")

// 4) 字形框补齐为行框：12pt 的字形框按 16pt 行框计算，间距从行框算起。
let glyph = NSRect(x: 400, y: 440, width: 1, height: 12)
let glyphFrame = CaretPlacement.frame(request(glyph))
require(glyphFrame.minY == glyph.minY - 2 - size.height - 8,
        "normalizes the glyph box to a line box before applying the gap: \(glyphFrame)")

// 5) 右边缘：镜像到插入点左侧，且整块不越界。
let rightEdge = NSRect(x: 1400, y: 440, width: 1, height: 16)
let mirrored = CaretPlacement.frame(request(rightEdge))
require(mirrored.maxX <= 1400 - 8 + 0.001, "mirrors to the left of the caret at the right edge: \(mirrored)")
require(mirrored.maxX <= screen.maxX, "stays inside the visible frame: \(mirrored)")

// 6) HUD 形态：居中 + 优先向上。
let hudSize = NSSize(width: 60, height: 24)
let hud = CaretPlacement.frame(CaretPlacement.Request(
    caret: middle, panelSize: hudSize, visible: screen,
    preferBelow: false, align: .centered, gap: 8))
require(hud.midX == middle.midX, "centered alignment centers on the caret: \(hud)")
require(hud.minY == middle.maxY + 8, "HUD prefers above: \(hud)")

// 7) 两侧都放不下但面板装得下：夹进可视区，绝不越界。
let cramped = NSRect(x: 40, y: 40, width: 600, height: 300)
let tallPanel = NSSize(width: 520, height: 200)
let clamped = CaretPlacement.frame(CaretPlacement.Request(
    caret: NSRect(x: 100, y: 200, width: 1, height: 16), panelSize: tallPanel,
    visible: cramped, preferBelow: true, align: .leading, gap: 8))
require(clamped.minY >= cramped.minY && clamped.maxY <= cramped.maxY + 0.001,
        "vertical clamping respects the visible frame: \(clamped)")
require(clamped.minX >= cramped.minX && clamped.maxX <= cramped.maxX + 0.001,
        "horizontal clamping respects the visible frame: \(clamped)")

// 7b) 面板比可视区还高（极端小窗）：贴住可视区起点，不越出上边。
let tiny = NSRect(x: 40, y: 40, width: 300, height: 60)
let oversized = CaretPlacement.frame(CaretPlacement.Request(
    caret: NSRect(x: 100, y: 70, width: 1, height: 16), panelSize: tallPanel,
    visible: tiny, preferBelow: true, align: .leading, gap: 8))
require(oversized.minY == tiny.minY && oversized.minX == tiny.minX,
        "an oversized panel is pinned to the visible origin: \(oversized)")

// 8) 副屏：使用传入的 visibleFrame，而不是主屏。
let secondary = NSRect(x: 1440, y: 0, width: 1280, height: 800)
let onSecondary = CaretPlacement.frame(request(NSRect(x: 1500, y: 400, width: 1, height: 16),
                                               visible: secondary))
require(onSecondary.minX >= secondary.minX && onSecondary.maxX <= secondary.maxX,
        "uses the visible frame of the target screen: \(onSecondary)")

// 9) 回退链（报告219）：本轮解析 → 上次位置 → 鼠标，鼠标只在最后一档。
let caretLine = NSRect(x: 100, y: 420, width: 2, height: 16)
let previousLine = NSRect(x: 300, y: 300, width: 2, height: 16)
let mouse = NSPoint(x: 900, y: 90)
let first = CaretPlacement.fallback(current: caretLine, previous: previousLine, mouse: mouse)
require(first.source == .resolved && first.rect == caretLine, "resolved caret wins: \(first)")
let second = CaretPlacement.fallback(current: nil, previous: previousLine, mouse: mouse)
require(second.source == .previous && second.rect == previousLine,
        "falls back to the last known caret, not the mouse: \(second)")
let third = CaretPlacement.fallback(current: nil, previous: nil, mouse: mouse)
require(third.source == .mouse && third.rect.minX == mouse.x && third.rect.minY == mouse.y,
        "uses the mouse only when nothing else is known: \(third)")

print("PASS caret-placement: below-first, flip, glyph normalization, right-edge mirror, HUD centered-above, clamping, secondary screen, fallback order")
