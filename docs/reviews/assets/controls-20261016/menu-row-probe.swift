import AppKit
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for (theme, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let row = InputModeMenuView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    row.mode = "混输"
    guard let appearance = NSAppearance(named: name),
        NSImage(systemSymbolName: "chevron.forward", accessibilityDescription: nil) != nil else { exit(1) }
    row.appearance = appearance
    for state in ["normal", "highlight", "disabled"] {
        row.isEnabled = state != "disabled"
        if state == "highlight", let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            row.mouseEntered(with: event)
        }
        var data: Data?
        appearance.performAsCurrentDrawingAppearance {
            let image = NSImage(size: row.bounds.size, flipped: true) { rect in
                NSColor.windowBackgroundColor.setFill(); rect.fill()
                row.draw(rect)
                return true
            }
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                data = rep.representation(using: .png, properties: [:])
            }
        }
        guard let data else { exit(1) }
        try data.write(to: output.appendingPathComponent("mode-\(theme)-\(state).png"))
    }
}
print("PASS offscreen system-symbol menu row; simulated highlight, no desktop events")
