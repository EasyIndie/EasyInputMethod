// Design-only AppKit renderer. Does not link IMK, read preferences, or send input.
import AppKit

final class Canvas: NSView { override var isFlipped: Bool { true } }
final class DesignWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
func luminance(_ rgb: [CGFloat]) -> CGFloat {
    let linear=rgb.map { $0 <= 0.04045 ? $0/12.92 : pow(($0+0.055)/1.055,2.4) }
    return linear[0]*0.2126 + linear[1]*0.7152 + linear[2]*0.0722
}
func contrast(_ foreground: NSColor, _ background: NSColor) -> CGFloat {
    guard let fg=foreground.usingColorSpace(.sRGB),let bg=background.usingColorSpace(.sRGB) else {return 0}
    let backdrop=[bg.redComponent,bg.greenComponent,bg.blueComponent]
    let composited=zip([fg.redComponent,fg.greenComponent,fg.blueComponent],backdrop).map { $0*fg.alphaComponent+$1*(1-fg.alphaComponent) }
    let a=luminance(composited),b=luminance(backdrop)
    return (max(a,b)+0.05)/(min(a,b)+0.05)
}
func secondaryInformationColor() -> NSColor {
    let secondary=NSColor.secondaryLabelColor
    return contrast(secondary,.windowBackgroundColor) >= 4.5 ? secondary : .labelColor
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, size: CGFloat = 13,
          secondary: Bool = false, bold: Bool = false, height: CGFloat = 34) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.frame = NSRect(x:x,y:y,width:w,height:height)
    field.font = bold ? .boldSystemFont(ofSize:size) : .systemFont(ofSize:size)
    field.textColor = secondary ? secondaryInformationColor() : .labelColor
    return field
}
func addText(_ view: NSView, _ value: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
             size: CGFloat = 13, secondary: Bool = false, bold: Bool = false) {
    view.addSubview(text(value,x,y,w,size:size,secondary:secondary,bold:bold))
}
func popup(_ values: [String], _ x: CGFloat, _ y: CGFloat, _ w: CGFloat) -> NSPopUpButton {
    let control=NSPopUpButton(frame:NSRect(x:x,y:y,width:w,height:28),pullsDown:false)
    control.addItems(withTitles:values);return control
}
func check(_ title: String, _ view: NSView, _ x: CGFloat, _ y: CGFloat, on: Bool = false) {
    let control=NSButton(checkboxWithTitle:title,target:nil,action:nil)
    control.frame=NSRect(x:x,y:y,width:500,height:24);control.state=on ? .on : .off
    view.addSubview(control)
}
func button(_ title: String, _ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat = 100,
            primary: Bool = false, enabled: Bool = true, destructive: Bool = false) -> NSButton {
    let control=NSButton(title:title,target:nil,action:nil)
    control.bezelStyle = .rounded;control.frame=NSRect(x:x,y:y,width:w,height:30)
    control.isEnabled=enabled;control.hasDestructiveAction=destructive
    if primary { control.keyEquivalent="\r" }
    view.addSubview(control);return control
}
func field(_ value: String, _ view: NSView, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
           enabled: Bool = true) -> NSTextField {
    let control=NSTextField(string:value);control.frame=NSRect(x:x,y:y,width:w,height:26)
    control.isEnabled=enabled;control.font = .systemFont(ofSize:13)
    view.addSubview(control);return control
}
func separator(_ view: NSView, _ y: CGFloat, _ w: CGFloat, x: CGFloat = 24) {
    let box=NSBox(frame:NSRect(x:x,y:y,width:w,height:1));box.boxType = .separator;view.addSubview(box)
}
func symbol(_ name: String, _ view: NSView, _ x: CGFloat, _ y: CGFloat,
            size: CGFloat = 16, tint: NSColor = .secondaryLabelColor) {
    let image=NSImageView(frame:NSRect(x:x,y:y,width:size,height:size))
    image.image=NSImage(systemSymbolName:name,accessibilityDescription:name)
    image.contentTintColor=tint;view.addSubview(image)
}
final class Panes: NSObject, NSToolbarDelegate {
    let names=["输入","候选","快捷键","词库"]
    let symbols=["keyboard","text.bubble","command","character.book.closed"]
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { names.map{.init($0)} }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { names.map{.init($0)} }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { names.map{.init($0)} }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let index=names.firstIndex(of:id.rawValue) else {return nil}
        let item=NSToolbarItem(itemIdentifier:id);item.label=names[index]
        item.image=NSImage(systemSymbolName:symbols[index],accessibilityDescription:names[index])
        item.autovalidates=false;item.isEnabled=true
        return item
    }
}
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
let output=URL(fileURLWithPath:CommandLine.arguments[1])
let iconPath=CommandLine.arguments[2]
let panes=Panes()
var windows:[NSWindow]=[]
var manifest:[[String:Any]]=[]
func window(_ title: String, _ width: CGFloat, _ height: CGFloat, _ appearance: NSAppearance,
            pane: String? = nil, borderless: Bool = false) -> (NSWindow,Canvas) {
    let styles: NSWindow.StyleMask = borderless ? [.borderless] : [.titled,.closable]
    let win=DesignWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:styles,backing:.buffered,defer:false)
    win.title=title;win.appearance=appearance;win.backgroundColor = .windowBackgroundColor
    win.isReleasedWhenClosed=false
    if let pane {
        win.toolbarStyle = .preference
        let bar=NSToolbar(identifier:"design-\(pane)");bar.delegate=panes
        bar.displayMode = .iconAndLabel;bar.allowsUserCustomization=false;bar.autosavesConfiguration=false
        win.toolbar=bar;bar.selectedItemIdentifier = .init(pane)
    }
    let view=Canvas(frame:NSRect(x:0,y:0,width:width,height:height));win.contentView=view
    if borderless {
        win.isOpaque=false;win.backgroundColor = .clear
        let surface=NSBox(frame:view.bounds);surface.boxType = .custom
        surface.titlePosition = .noTitle;surface.cornerRadius=10;surface.borderWidth=0.5
        surface.borderColor = .separatorColor;surface.fillColor = .windowBackgroundColor
        view.addSubview(surface)
    }
    windows.append(win);return (win,view)
}
func capture(_ win: NSWindow,_ name: String,_ appearance: NSAppearance,_ note: String = "AppKit native controls; offscreen non-key window") throws {
    win.displayIfNeeded();win.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(until:Date().addingTimeInterval(0.06))
    guard let view=win.contentView?.superview,
          let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {fatalError("No native frame")}
    appearance.performAsCurrentDrawingAppearance {view.cacheDisplay(in:view.bounds,to:rep)}
    guard let png=rep.representation(using:.png,properties:[:]) else {fatalError("No PNG")}
    try png.write(to:output.appendingPathComponent(name+".png"))
    manifest.append(["file":name+".png","widthPt":view.bounds.width,"heightPt":view.bounds.height,
                     "pixelsWide":rep.pixelsWide,"pixelsHigh":rep.pixelsHigh,"scope":note])
}
func settings(_ pane: String,_ a: NSAppearance) -> NSWindow {
    let h:CGFloat = pane == "输入" ? 500 : pane == "快捷键" ? 388 : 370
    let (win,v)=window(pane+" — 萤火虫",650,h,a,pane:pane)
    if pane == "输入" {
        addText(v,"默认输入",24,18,250,bold:true)
        addText(v,"输入模式",42,53,140)
        let mode=NSSegmentedControl(labels:["混输","五笔","拼音"],trackingMode:.selectOne,target:nil,action:nil)
        mode.frame=NSRect(x:366,y:46,width:244,height:30);mode.selectedSegment=0;v.addSubview(mode)
        addText(v,"五笔优先，想不起编码时用拼音兜底。",42,87,555,size:12,secondary:true)
        separator(v,121,566,x:42)
        addText(v,"输出字形",42,143,180);v.addSubview(popup(["简体","繁体"],466,132,148))
        addText(v,"标点",42,188,180);v.addSubview(popup(["中文标点","英文标点"],466,177,148))
        check("默认全角 ASCII",v,42,224)
        addText(v,"当前会话可用快捷键临时切换。",63,252,500,size:12,secondary:true)
        separator(v,294,602)
        addText(v,"五笔与拼音",24,316,200,bold:true)
        check("四码唯一时自动上屏",v,42,347,on:true)
        addText(v,"Z 键",42,390,180);v.addSubview(popup(["万能键","关闭"],466,379,148))
        check("模糊音",v,42,428)
        addText(v,"使用当前支持的基础音节规则。",63,457,500,size:12,secondary:true)
    } else if pane == "候选" {
        addText(v,"候选显示",24,20,200,bold:true)
        addText(v,"每页候选数",42,59,200)
        _=field("9",v,508,49,52)
        let step=NSStepper(frame:NSRect(x:566,y:47,width:22,height:30));step.minValue=3;step.maxValue=9;step.integerValue=9;v.addSubview(step)
        check("逗号 / 句号翻页",v,42,104,on:true)
        separator(v,151,602)
        addText(v,"外观",24,174,200,bold:true)
        addText(v,"外观选择",42,215,180);v.addSubview(popup(["跟随系统","浅色","深色"],428,204,188))
        addText(v,"默认尊重系统外观。浅色与深色选项仅为现有兼容设置。",42,252,550,size:12,secondary:true)
        addText(v,"对比度、透明度和动态效果由 macOS 辅助功能设置控制。",42,297,550,size:12,secondary:true)
    } else if pane == "快捷键" {
        addText(v,"输入快捷键",24,20,220,bold:true)
        let rows=[("输入模式","⌃⇧M"),("中英切换","单独 ⇧"),("全 / 半角","⇧Space"),("中英标点","⌃."),("简 / 繁","⌃⇧F")]
        for (i,row) in rows.enumerated() {
            let y:CGFloat=60+CGFloat(i)*44
            addText(v,row.0,42,y+5,205);addText(v,row.1,353,y+5,122);_=button("编辑…",v,498,y-6,114)
        }
        separator(v,293,602)
        addText(v,"通过“编辑…”修改或关闭绑定。非法／重复设置不保存。",42,315,550,size:12,secondary:true)
        addText(v,"系统及其他应用的快捷键冲突仍需实际使用确认。",42,348,550,size:12,secondary:true)
    } else {
        addText(v,"用户词库",24,20,200,bold:true)
        addText(v,"词条只保存在这台 Mac，不上传输入内容。",42,56,550,size:12,secondary:true)
        _=button("新增词条…",v,42,97,122);_=button("删除词条…",v,180,97,122,destructive:false)
        _=button("导入…",v,42,151,122);_=button("导出…",v,180,151,122)
        addText(v,"纠错时精确删除旧条目，再添加正确词条。",42,207,550,size:12,secondary:true)
        separator(v,252,602)
        addText(v,"本地工具",24,276,200,bold:true)
        _=button("拼音反查…",v,42,310,122)
    }
    return win
}
func codeLabel(_ value:String,_ v:NSView,_ x:CGFloat,_ y:CGFloat,_ width:CGFloat,size:CGFloat=16) {
    let label=text(value,x,y,width,size:size,bold:true)
    label.font=NSFont.monospacedSystemFont(ofSize:size,weight:.semibold);v.addSubview(label)
}
func rootPairs(_ v:NSView,_ roots:[String],_ keys:[String],_ x:CGFloat,_ y:CGFloat,_ step:CGFloat) {
    for (i,root) in roots.enumerated() {
        let column=x+CGFloat(i)*step
        let glyph=text(root,column,y,step-8,size:root=="识别码" ? 10 : 15,secondary:true,height:22)
        glyph.alignment = .center;v.addSubview(glyph)
        let key=text(keys[i],column,y+24,step-8,size:11,secondary:true,height:18)
        key.font=NSFont.monospacedSystemFont(ofSize:11,weight:.regular)
        key.alignment = .center;v.addSubview(key)
    }
}
func candidate(_ a:NSAppearance,vertical:Bool=false,empty:Bool=false,collapsed:Bool=false,partial:Bool=false,page:Int=1,pages:Int=12) -> NSWindow {
    let expanded=vertical
    let (win,v)=window("长词学习区布局稿",420,expanded ? 520 : 264,a,borderless:true)
    addText(v,"zhonghuarenmingongheguo",16,8,278,size:12)
    symbol("chevron.left",v,320,11,size:10,tint:.disabledControlTextColor)
    addText(v,"1/3",342,9,35,size:11,secondary:true)
    symbol("chevron.right",v,391,11,size:10,tint:secondaryInformationColor())
    addText(v,"1",16,40,18,size:11,bold:true)
    addText(v,"中华人民共和国",42,36,360,size:17,bold:true)
    addText(v,"2",16,77,18,size:11,secondary:true)
    addText(v,"中华人民共和国成立",42,73,360,size:17)
    addText(v,"3",16,114,18,size:11,secondary:true)
    addText(v,"中华",42,110,360,size:17)
    separator(v,147,388,x:16)
    addText(v,"完整码",16,160,56,size:11,secondary:true)
    let code=text("KWWL",80,157,100,size:13);code.font = .monospacedSystemFont(ofSize:13,weight:.medium);v.addSubview(code)
    rootPairs(v,["中","华","人","国"],["K","W","W","L"],16,186,74)
    addText(v,"取前三字和末字的首码",16,231,388,size:11,secondary:true)
    if expanded {
        separator(v,258,388,x:16)
        symbol("chevron.down",v,16,273,size:10,tint:secondaryInformationColor())
        addText(v,"逐字拆分",34,269,220,size:12,secondary:true)
        let scroll=NSScrollView(frame:NSRect(x:16,y:297,width:388,height:185))
        scroll.hasVerticalScroller=true;scroll.autohidesScrollers=false;scroll.drawsBackground=false
        let content=Canvas(frame:NSRect(x:0,y:0,width:365,height:380))
        let chars=["中","华","人","民","共","和","国"]
        let codes=["KHK","WXFJ","WWWW","NAV","AWU","TKG","LGYI"]
        var row:CGFloat=0
        for i in 0..<7 {
            symbol(i==1 ? "chevron.down" : "chevron.right",content,0,row+7,size:9,tint:secondaryInformationColor())
            addText(content,chars[i],20,row+2,28,size:13,bold:i==1)
            let code=text(codes[i],62,row+3,100,size:12,secondary:true);code.font = .monospacedSystemFont(ofSize:12,weight:.regular);content.addSubview(code)
            if i==1 {
                rootPairs(content,["亻","匕","十","识别码"],["W","X","F","J"],20,row+30, seventy())
                addText(content,"J：末笔点 · 上下结构",20,row+78,330,size:11,secondary:true)
                row += 110
            } else {row += 38}
        }
        scroll.documentView=content;v.addSubview(scroll)
        addText(v,"共7字 · 向下滚动查看更多",16,493,388,size:11,secondary:true)
    } else {
        symbol("chevron.right",v,319,162,size:10,tint:secondaryInformationColor())
        addText(v,"逐字拆分",336,158,74,size:11,secondary:true)
    }
    return win
}
func seventy()->CGFloat {70}
func learningSettings(_ a:NSAppearance)->NSWindow {
    let (win,v)=window("候选 — 萤火虫",480,210,a)
    addText(v,"五笔学习区",24,22,420,size:13,bold:true)
    let check=NSButton(checkboxWithTitle:"显示编码与拆字说明",target:nil,action:nil)
    check.frame=NSRect(x:24,y:58,width:420,height:24);check.state = .off;v.addSubview(check)
    addText(v,"显示当前候选的五笔信息，适用于所有输入模式。",24,90,430,size:12,secondary:true)
    addText(v,"显示 / 隐藏快捷键",24,136,170,size:13)
    addText(v,"未设置",208,136,90,size:13,secondary:true)
    _ = button("设置…",v,328,131,126)
    return win
}
func menuLayout(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("NSMenu排版规格",288,258,a,borderless:true)
    v.wantsLayer=true;v.layer?.cornerRadius=8;v.layer?.masksToBounds=true
    let rows=[("输入模式","混输"),("中文输入","⇧"),("全角 ASCII","⇧Space"),("繁体输出","⌃⇧F"),("中文标点","⌃.")]
    for (i,row) in rows.enumerated() {
        let y:CGFloat=12+CGFloat(i)*31
        if i==1 || i==4 {symbol("checkmark",v,12,y+1,size:13,tint:.labelColor)}
        addText(v,row.0,34,y,160)
        let key=text(row.1,181,y,i==0 ? 76 : 92,size:12,secondary:true);key.alignment = .right;v.addSubview(key)
        if i==0 {symbol("chevron.right",v,269,y+3,size:11,tint:.labelColor)}
    }
    separator(v,173,264,x:12)
    addText(v,"设置…",34,187,220);addText(v,"关于萤火虫…",34,223,220)
    return win
}
func modeMenuLayout(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("输入模式子菜单规格",156,110,a,borderless:true)
    for (i,name) in ["混输","五笔","拼音"].enumerated() {
        let y: CGFloat = 12+CGFloat(i)*31
        if i==0 {symbol("checkmark",v,12,y+1,size:13,tint:.labelColor)}
        addText(v,name,34,y,106)
    }
    return win
}
func wordSheet(_ a: NSAppearance,deletion: Bool = false) -> NSWindow {
    let (win,v)=window("sheet内容稿",432,300,a,borderless:true)
    v.wantsLayer=true;v.layer?.cornerRadius=12;v.layer?.masksToBounds=true
    addText(v,deletion ? "删除用户词条" : "新增用户词条",24,22,380,size:15,bold:true)
    addText(v,deletion ? "仅删除指定用户词条，内置数据不受影响。" : "使用完整编码；输入内容只存本地。",24,58,380,size:12,secondary:true)
    addText(v,"输入方案",24,101,100);v.addSubview(popup(["五笔","拼音"],133,90,273))
    addText(v,"完整编码",24,143,100);_=field("wqiy",v,133,133,269)
    addText(v,"词条",24,185,100);_=field("你",v,133,175,269)
    _=button("取消",v,209,246,88,primary:deletion)
    _=button(deletion ? "删除词条" : "添加",v,306,246,103,primary:!deletion,destructive:deletion)
    return win
}
func lookup(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("拼音反查",450,250,a)
    addText(v,"要查询的文字",24,20,300)
    _=field("你好",v,24,57,294);_=button("反查",v,330,54,96,primary:true)
    separator(v,108,402)
    addText(v,"你好",24,134,200,size:20,bold:true)
    addText(v,"nihao",24,174,250,size:13,secondary:true)
    _=button("复制读音",v,316,191,112)
    return win
}
func about(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("关于萤火虫",450,324,a)
    let image=NSImageView(frame:NSRect(x:188,y:18,width:74,height:74));image.image=NSImage(contentsOfFile:iconPath);v.addSubview(image)
    let name=text("萤火虫",0,107,450,size:22,bold:true);name.alignment = .center;v.addSubview(name)
    let version=text("0.1.0 · 开源中文输入法",0,148,450,size:12,secondary:true);version.alignment = .center;v.addSubview(version)
    let tagline=text("五笔优先，拼音兜底。默认离线。",0,187,450,size:13);tagline.alignment = .center;v.addSubview(tagline)
    _=button("复制诊断",v,99,229,116);_=button("反馈问题…",v,231,229,120)
    let source=text("GPL-3.0-or-later",0,287,450,size:11,secondary:true);source.alignment = .center;v.addSubview(source)
    return win
}
func feedback(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("词库 — 操作结果",650,242,a)
    symbol("exclamationmark.triangle",v,26,28,size:21,tint:.systemOrange)
    addText(v,"未导入用户词库",58,26,550,bold:true)
    addText(v,"第24行编码格式不正确。已有词库未改变。",58,61,550,size:12,secondary:true)
    _=button("重新选择文件…",v,54,113,158)
    separator(v,164,602)
    symbol("checkmark.circle",v,26,186,size:17,tint:.systemGreen)
    addText(v,"已导出用户词库",54,186,500,size:12)
    return win
}
func shortcutSheet(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("快捷键编辑sheet内容",432,227,a,borderless:true)
    addText(v,"切换输入模式",24,22,380,size:15,bold:true)
    addText(v,"修改现有绑定，或输入 none 关闭这个动作。",24,60,380,size:12,secondary:true)
    addText(v,"快捷键",24,108,100);_=field("ctrl+shift+m",v,122,98,280)
    _=button("取消",v,208,174,88);_=button("确定",v,306,174,102,primary:true)
    return win
}
func components(_ a: NSAppearance) -> NSWindow {
    let (win,v)=window("原生控件状态",650,295,a)
    addText(v,"普通",24,21,120,size:12,secondary:true);_=button("导出…",v,150,14,110)
    addText(v,"默认操作",340,21,120,size:12,secondary:true);_=button("添加",v,467,14,110,primary:true)
    addText(v,"禁用",24,80,120,size:12,secondary:true);_=button("复制读音",v,150,72,110,enabled:false)
    addText(v,"危险操作",340,80,120,size:12,secondary:true);_=button("删除词条",v,467,72,110,destructive:true)
    addText(v,"输入字段",24,139,120,size:12,secondary:true);let input=field("wqiy",v,150,128,427);input.setAccessibilityLabel("完整编码")
    addText(v,"进行中",24,198,120,size:12,secondary:true)
    let progress=NSProgressIndicator(frame:NSRect(x:151,y:199,width:20,height:20));progress.style = .spinning
    progress.isIndeterminate=true;progress.startAnimation(nil);v.addSubview(progress)
    addText(v,"正在导入…",182,199,300,size:12,secondary:true)
    addText(v,"悬停、按下和键盘焦点使用系统状态；离屏稿不伪造实机事件。",24,251,602,size:11,secondary:true)
    return win
}
var colorModes:[String:Any]=[:]
let appearances:[(String,NSAppearance.Name)]=[("light",.aqua),("dark",.darkAqua),("light-high",.accessibilityHighContrastAqua),("dark-high",.accessibilityHighContrastDarkAqua)]
for (name,appearanceName) in appearances {
    guard let appearance=NSAppearance(named:appearanceName) else {fatalError("No appearance")}
    var colors:[String:Any]=[:]
    appearance.performAsCurrentDrawingAppearance {
        let roles:[(String,NSColor)]=[("windowBackground",.windowBackgroundColor),("contentBackground",.controlBackgroundColor),
          ("text",.labelColor),("secondary",.secondaryLabelColor),("informationSecondary",secondaryInformationColor()),("disabled",.disabledControlTextColor),
          ("separator",.separatorColor),("accent",.controlAccentColor),("selection",.selectedContentBackgroundColor),
          ("focus",.keyboardFocusIndicatorColor),("errorSymbol",.systemRed),("warningSymbol",.systemOrange),("successSymbol",.systemGreen)]
        for (role,color) in roles {
            if let rgb=color.usingColorSpace(.sRGB) {
                colors[role]=["hex":String(format:"#%02X%02X%02X",Int((rgb.redComponent*255).rounded()),Int((rgb.greenComponent*255).rounded()),Int((rgb.blueComponent*255).rounded())),"alpha":rgb.alphaComponent,"contrastOnWindowBackground":contrast(color,.windowBackgroundColor)]
            }
        }
    }
    colorModes[name]=colors
    let full=name=="light" || name=="dark"
    var exportError: Error?
    appearance.performAsCurrentDrawingAppearance {
        do {
            try capture(candidate(appearance),"long-summary-\(name)",appearance,"Long word summary; static layout example")
            if full {
                try capture(candidate(appearance,vertical:true),"long-expanded-\(name)",appearance,"Native scrolling content with expanded character; teaching roots are draft examples")
            }
        } catch {exportError=error}
    }
    if let error=exportError {throw error}
}
let report:[String:Any]=["status":"design-only, not implemented","system":"AppKit/macOS27 runtime",
 "shownWindows":false,"inputSent":false,"userConfigurationAccessed":false,"captures":manifest,
 "limits":["Window chrome is non-key/offscreen; does not prove active focus/hover/press", "No desktop backdrop for optical material validation", "No real VoiceOver or modal-flow validation", "Menu is layout specification, not screenshot of NSMenu popup"]]
try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-render-report.json"))
let tokens:[String:Any]=["source":"NSColor dynamic semantic APIs","observedRuntime":"macOS27",
 "referenceOnly":true,"hardcodedProductionColors":false,"modes":colorModes]
try JSONSerialization.data(withJSONObject:tokens,options:[.prettyPrinted,.sortedKeys]).write(to:output.appendingPathComponent("native-color-reference.json"))
print("Exported \(manifest.count) native design frames; zero shown windows, input, or config access")
