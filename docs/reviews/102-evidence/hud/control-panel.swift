import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class Dot: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 8, yRadius: 8)
        path.fill()
    }
}

// 与 StateHUDController 相同的窗口配置
let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 32),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
panel.isFloatingPanel = true
panel.level = .popUpMenu
panel.hidesOnDeactivate = false
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.ignoresMouseEvents = true
panel.animationBehavior = .none
panel.contentView = Dot()

// 放在内建屏 (200,300) 的 AppKit 坐标处（内建屏高 800）
panel.setFrame(NSRect(x: 200, y: 300, width: 400, height: 32), display: false)
panel.alphaValue = 1
panel.orderFrontRegardless()

print("panel frame:", panel.frame, "visible:", panel.isVisible)
DispatchQueue.main.asyncAfter(deadline: .now() + 6) { app.terminate(nil) }
app.run()
