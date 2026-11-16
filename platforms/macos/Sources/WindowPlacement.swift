import Cocoa

/// 窗口落点（ADR-365 / 报告 290 P2-6）：练习、指南、设置这类"自建窗口"统一按
/// **鼠标所在屏优先、否则主屏**居中，并把整窗夹进该屏可见区域。
///
/// 为什么不用 `NSWindow.center()`：它只按窗口当前所在屏（新建窗口按主屏）居中，
/// 双屏/上下排列时窗口会落到另一块屏（甚至负坐标），用户看起来像"窗口没打开"。
enum WindowPlacement {
    /// 鼠标落在哪块屏；不在任何屏内返回 nil（调用方回退主屏/第一块）。
    static func screenIndex(mouse: NSPoint, frames: [NSRect]) -> Int? {
        frames.firstIndex { NSMouseInRect(mouse, $0, false) }
    }

    /// 在给定可见区域内居中的窗口原点，并把整窗夹进可见区域（超大窗口贴左上）。
    static func origin(size: NSSize, visible: NSRect) -> NSPoint {
        let maxX = max(visible.minX, visible.maxX - size.width)
        let maxY = max(visible.minY, visible.maxY - size.height)
        let x = min(max(visible.midX - size.width / 2, visible.minX), maxX)
        let y = min(max(visible.midY - size.height / 2, visible.minY), maxY)
        return NSPoint(x: x, y: y)
    }

    /// 选中屏幕：鼠标所在屏 → 主屏 → 第一块；然后按 `origin(size:visible:)` 落点。
    static func place(_ window: NSWindow, screens: [NSScreen] = NSScreen.screens,
                      mouse: NSPoint = NSEvent.mouseLocation) {
        guard !screens.isEmpty else {
            window.center()
            return
        }
        let index = screenIndex(mouse: mouse, frames: screens.map(\.frame))
            ?? screens.firstIndex(where: { $0 == NSScreen.main })
            ?? 0
        let visible = screens[min(index, screens.count - 1)].visibleFrame
        var frame = window.frame
        frame.origin = origin(size: frame.size, visible: visible)
        window.setFrame(frame, display: false)
    }
}
