// 显示器布局探针：输出每块屏幕的 frame/visibleFrame/缩放/是否主屏，供多屏验收判定候选窗落点。
// 仅开发/验收使用，不进入产品。
import AppKit

var items: [[String: Any]] = []
for (index, screen) in NSScreen.screens.enumerated() {
    let frame = screen.frame
    let visible = screen.visibleFrame
    items.append([
        "index": index,
        "name": screen.localizedName,
        "is_main": screen == NSScreen.main,
        "frame": [frame.origin.x, frame.origin.y, frame.size.width, frame.size.height],
        "visible": [visible.origin.x, visible.origin.y, visible.size.width, visible.size.height],
        "scale": screen.backingScaleFactor,
    ])
}
let data = try? JSONSerialization.data(withJSONObject: ["screens": items], options: [.sortedKeys])
print(String(data: data ?? Data(), encoding: .utf8) ?? "{}")
