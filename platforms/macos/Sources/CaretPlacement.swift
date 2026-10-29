import Foundation

/// 光标跟随的唯一几何决策点（报告216 §11.1、ADR-301）。
///
/// HUD 与候选窗都只调这里，避免各自维护一套间距与翻转规则。纯函数：
/// 输入 `Request` 全部确定，输出面板 frame，不做 IO、不碰 AppKit 全局状态。
///
/// 规则：
/// 1. **归一化行框**：`IMKTextInput` 给的是字形框（不含下伸部与行距），先按
///    `max(height, minimumLineHeight)` 以中线为中心扩成行框，再谈间距。
/// 2. **纵向**：优先 `preferBelow`；放不下翻到另一侧；两侧都放不下时选空间大的一侧并夹在可视区内。
/// 3. **横向**：按 `align` 摆放；右侧越界时镜像到插入点左侧（而不是硬夹，避免反盖住插入点）；仍越界才夹住。
/// 4. **不变量**：结果整体在 `visible` 内；未被夹住时与行框的间距恰为 `gap`。
enum CaretPlacement {
    enum Alignment: Equatable {
        /// 面板左边缘对齐插入点（候选窗）。
        case leading
        /// 面板与插入点水平居中（HUD）。
        case centered
    }

    struct Request: Equatable {
        /// 客户端给出的插入点矩形（字形框，屏幕坐标，左下原点）。
        var caret: NSRect
        var panelSize: NSSize
        /// 目标屏的 `visibleFrame`（已排除菜单栏与 Dock）。
        var visible: NSRect
        /// true = 优先放在行下方（候选窗）；false = 优先放在行上方（HUD）。
        var preferBelow: Bool
        var align: Alignment
        /// 与行框之间的间距。
        var gap: CGFloat
        /// 行框最小高度：字形框通常比整行矮，用它补足下伸部与行距。
        var minimumLineHeight: CGFloat = 16

        init(caret: NSRect, panelSize: NSSize, visible: NSRect,
             preferBelow: Bool, align: Alignment, gap: CGFloat,
             minimumLineHeight: CGFloat = 16) {
            self.caret = caret
            self.panelSize = panelSize
            self.visible = visible
            self.preferBelow = preferBelow
            self.align = align
            self.gap = gap
            self.minimumLineHeight = minimumLineHeight
        }
    }

    /// 把客户端字形框扩成行框：高度不足时保持中线不动上下对称扩展。
    static func lineBox(_ caret: NSRect, minimumHeight: CGFloat) -> NSRect {
        guard caret.height < minimumHeight else { return caret }
        let extra = (minimumHeight - caret.height) / 2
        return NSRect(x: caret.minX, y: caret.minY - extra,
                      width: caret.width, height: minimumHeight)
    }

    /// 计算面板 frame（origin 为左下原点，与 `NSWindow.setFrame` 一致）。
    static func frame(_ request: Request) -> NSRect {
        let visible = request.visible
        let size = request.panelSize
        let line = lineBox(request.caret, minimumHeight: request.minimumLineHeight)

        var origin = NSPoint(x: horizontal(request, line: line), y: vertical(request, line: line))
        origin.x = min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width))
        origin.y = min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height))
        return NSRect(origin: origin, size: size)
    }

    private static func horizontal(_ request: Request, line: NSRect) -> CGFloat {
        let visible = request.visible
        let width = request.panelSize.width
        let desired: CGFloat
        switch request.align {
        case .centered: desired = line.midX - width / 2
        case .leading: desired = line.minX
        }
        if desired + width <= visible.maxX { return desired }
        // 右侧放不下：镜像到插入点左侧；再放不下才交给调用方的夹取。
        let mirrored = line.minX - width - request.gap
        if mirrored >= visible.minX { return mirrored }
        return visible.maxX - width
    }

    private static func vertical(_ request: Request, line: NSRect) -> CGFloat {
        let visible = request.visible
        let height = request.panelSize.height
        let below = line.minY - height - request.gap
        let above = line.maxY + request.gap
        let fitsBelow = below >= visible.minY
        let fitsAbove = above + height <= visible.maxY
        if request.preferBelow {
            if fitsBelow { return below }
            if fitsAbove { return above }
        } else {
            if fitsAbove { return above }
            if fitsBelow { return below }
        }
        // 两侧都放不下：选空间更大的一侧，由调用方夹进可视区。
        let spaceBelow = line.minY - visible.minY
        let spaceAbove = visible.maxY - line.maxY
        return spaceBelow >= spaceAbove ? below : above
    }

    /// 取不到光标时的回退顺序（报告219）：上一次成功的位置 → 鼠标。
    ///
    /// 鼠标几乎从来不是用户想要的位置：输入框有焦点、鼠标在别处时，跟着鼠标会把候选窗
    /// 放到屏幕上完全无关的角落。因此只在「本轮解析失败且没有任何历史位置」时才用鼠标。
    enum Fallback: String, Equatable {
        case resolved
        case previous
        case mouse
    }

    static func fallback(current: NSRect?, previous: NSRect?,
                         mouse: NSPoint) -> (rect: NSRect, source: Fallback) {
        if let current { return (current, .resolved) }
        if let previous { return (previous, .previous) }
        return (NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1), .mouse)
    }
}
