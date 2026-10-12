// 偏好设置面板（ADR-070 / ADR-075）：由 `ime_config_schema()` 驱动，界面零硬编码。
//
// 非模态、改动即时生效：写入只经 `ime_config_set()`（配置唯一写入路径），
// 变更广播由 `ConfigWatcher` 派发（ADR-058）。见 `docs/配置架构.md` §8/§9/§11。
//
// ADR-077/080：面板为「设置 / 词库」两段（帮助信息已移除，快捷键在设置项内即可见）。
// 新增分区只需扩展 `Section` 与 `sectionViews`。

import Cocoa
import ime

/// Schema 选项的 Swift 视图（只含元数据；当前值由各行从 `ime_config_get` 读取）。
struct SettingsOption {
    enum Kind {
        case bool
        case int(min: Int, max: Int)
        case choice(values: [String], labels: [String])
        case text
    }

    let key: String
    let title: String
    let doc: String
    let scope: Int
    let kind: Kind

    /// scope 显示名（与 FFI 的 `scope` 数值约定一致）。
    static let scopeTitles = ["输入引擎", "候选窗", "外观", "快捷键"]

    var scopeTitle: String {
        (0..<Self.scopeTitles.count).contains(scope) ? Self.scopeTitles[scope] : "其它"
    }
}

/// 从 C ABI 解析 Schema（唯一来源）；解析列表辅助。
enum SettingsSchema {
    static func options() -> [SettingsOption] {
        guard let schema = ime_config_schema(), let items = schema.pointee.items else { return [] }
        return (0..<Int(schema.pointee.len)).map { index in
            let item = items[index]
            let kind: SettingsOption.Kind
            switch item.value_type {
            case 0: kind = .bool
            case 1: kind = .int(min: Int(item.int_min), max: Int(item.int_max))
            case 2:
                kind = .choice(
                    values: list(item.enum_values), labels: list(item.enum_labels_zh))
            default: kind = .text
            }
            return SettingsOption(
                key: String(cString: item.key), title: String(cString: item.title_zh),
                doc: String(cString: item.doc_zh), scope: Int(item.scope), kind: kind)
        }
    }

    /// 解析 NUL 分隔的 UTF-8 列表（空串结束）。
    private static func list(_ pointer: UnsafePointer<CChar>?) -> [String] {
        guard let pointer else { return [] }
        var out: [String] = []
        var cursor = pointer
        while true {
            let value = String(cString: cursor)
            if value.isEmpty { break }
            out.append(value)
            cursor = cursor.advanced(by: strlen(cursor) + 1)
        }
        return out
    }
}

/// 一行设置：标题 + 控件 + 说明；控件类型由 Schema 决定，改动即时写回。
final class SettingRow: NSStackView, NSTextFieldDelegate {
    let option: SettingsOption
    private var checkbox: NSButton?
    private var popup: NSPopUpButton?
    private var stepper: NSStepper?
    private var numberLabel: NSTextField?
    private var textField: NSTextField?
    private var rawValues: [String] = []

    init(option: SettingsOption) {
        self.option = option
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 2

        let title = NSTextField(labelWithString: option.title)
        title.font = .systemFont(ofSize: 13)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .firstBaseline
        top.spacing = 10
        top.addArrangedSubview(title)
        if let control = buildControl() {
            control.setAccessibilityLabel(option.title)
            control.setAccessibilityHelp(option.doc)
            top.addArrangedSubview(control)
        }

        let help = NSTextField(wrappingLabelWithString: option.doc)
        help.font = .systemFont(ofSize: 11)
        help.textColor = ImeAppearance.secondaryText
        help.preferredMaxLayoutWidth = 430
        help.lineBreakMode = .byWordWrapping

        addArrangedSubview(top)
        addArrangedSubview(help)
        top.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    /// 按 Schema 类型构建控件；返回应加入标题行的视图。
    private func buildControl() -> NSView? {
        switch option.kind {
        case .bool:
            let box = NSButton(checkboxWithTitle: "", target: self, action: #selector(boolChanged(_:)))
            checkbox = box
            return box
        case .int(let min, let max):
            let value = NSTextField(labelWithString: "")
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            value.widthAnchor.constraint(equalToConstant: 22).isActive = true
            numberLabel = value
            let stepper = NSStepper()
            stepper.minValue = Double(min)
            stepper.maxValue = Double(max)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.target = self
            stepper.action = #selector(stepperChanged(_:))
            stepper.setAccessibilityLabel(option.title)
            stepper.setAccessibilityHelp(option.doc)
            self.stepper = stepper
            let box = NSStackView(views: [value, stepper])
            box.orientation = .horizontal
            box.spacing = 6
            box.alignment = .centerY
            return box
        case .choice(let values, let labels):
            rawValues = values
            let menu = NSPopUpButton()
            for (index, value) in values.enumerated() {
                menu.addItem(withTitle: index < labels.count ? labels[index] : value)
            }
            menu.target = self
            menu.action = #selector(popupChanged(_:))
            popup = menu
            return menu
        case .text:
            let field = NSTextField()
            field.placeholderString = "组合键，如 ctrl+shift+m；留空 = 关闭"
            field.font = .systemFont(ofSize: 12)
            field.delegate = self
            field.target = self
            field.action = #selector(textCommitted(_:))
            field.widthAnchor.constraint(equalToConstant: 190).isActive = true
            textField = field
            return field
        }
    }

    /// 从配置回读真实值并刷新控件（打开面板、或配置被其它入口改动时）。
    func reload() {
        let raw = ImeConfig.string(option.key) ?? ""
        switch option.kind {
        case .bool:
            checkbox?.state = raw == "true" ? .on : .off
        case .int:
            numberLabel?.stringValue = raw
            stepper?.intValue = Int32(raw) ?? 0
        case .choice(let values, _):
            if let index = values.firstIndex(of: raw) { popup?.selectItem(at: index) }
        case .text:
            textField?.stringValue = raw == "none" ? "" : raw
        }
    }

    // MARK: - 写回（唯一路径）

    @objc private func boolChanged(_ sender: NSButton) {
        write(sender.state == .on ? "true" : "false", toml: true)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        write(String(sender.integerValue), toml: true)
    }

    @objc private func popupChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard rawValues.indices.contains(index) else { return }
        write(rawValues[index], toml: false)
    }

    @objc private func textCommitted(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespaces)
        write(trimmed.isEmpty ? "none" : trimmed, toml: false)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field === textField else { return }
        textCommitted(field)
    }

    private func write(_ value: String, toml: Bool) {
        let ok = toml ? ImeConfig.setToml(option.key, value) : ImeConfig.setString(option.key, value)
        if !ok {
            SettingsPanel.shared.reportFailure(option.key)
            reload()
        }
    }
}

/// 设置面板（进程内单例；重复打开只前置已有窗口）。
///
/// ADR-070/077/080：非模态设置窗口，分段承载 设置 / 词库。
final class SettingsPanel: NSObject, NSWindowDelegate {
    static let shared = SettingsPanel()

    /// 分区。新增分区 = 加一个 case + 一个 builder（保持可扩展、菜单不再膨胀）。
    private enum Section: Int, CaseIterable {
        case settings, dictionary
        var title: String {
            switch self {
            case .settings: return "设置"
            case .dictionary: return "词库"
            }
        }
    }

    private var window: NSPanel?
    private var rows: [SettingRow] = []
    private var statusLabel: NSTextField?
    private weak var session: ImeSession?
    private var segmented: NSSegmentedControl?
    private var contentHost: NSView?
    private var sectionViews: [NSView] = []

    private override init() { super.init() }

    /// 构建窗口（幂等，不前置）；供 `show()` 与冒烟测试复用。
    func prepare() {
        guard window == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "萤火虫 · 偏好设置"
        panel.contentMinSize = NSSize(width: 520, height: 440)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        buildContent(panel)
        panel.center()
        window = panel
        ImeAppearance.applyTheme(to: panel)
        // 其它入口（快捷键/菜单/外部编辑）改配置时，保持面板控件同步。
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in self?.configChanged(key) }
    }

    /// 打开面板；`session` 供「词库」分区使用（可为 nil，此时按钮不可用）。
    func show(session: ImeSession?) {
        self.session = session
        prepare()
        rows.forEach { $0.reload() }
        if let window { ImeAppearance.applyTheme(to: window) }
        setStatus("", isError: false)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 已构建的行数（供冒烟测试断言）。
    var rowCount: Int { rows.count }
    var displayedOptionKeys: [String] { rows.map { $0.option.key } }
    var minimumContentSize: NSSize { window?.contentMinSize ?? .zero }
    var configuredAppearanceForTesting: NSAppearance.Name? { window?.appearance?.name }

    func renderLongErrorForTesting(appearance: NSAppearance) -> NSBitmapImageRep? {
        prepare()
        setStatus(String(repeating: "保存失败：请检查文件权限或修复快捷键冲突。", count: 5), isError: true)
        defer { setStatus("", isError: false) }
        return renderSnapshotForTesting(appearance: appearance)
    }

    func renderMinimumSizeForTesting(appearance: NSAppearance) -> NSBitmapImageRep? {
        prepare()
        guard let window else { return nil }
        let original = window.contentView?.bounds.size ?? window.contentMinSize
        window.setContentSize(window.contentMinSize)
        defer { window.setContentSize(original) }
        return renderLongErrorForTesting(appearance: appearance)
    }

    /// 供冒烟测试断言：分区数。
    var sectionCount: Int { sectionViews.count }

    /// 供自测：在给定外观下渲染面板内容为位图，用于亮/暗主题对比度断言。
    func renderSnapshotForTesting(appearance: NSAppearance) -> NSBitmapImageRep? {
        prepare()
        rows.forEach { $0.reload() }
        guard let window, let view = window.contentView, view.bounds.width > 1,
            view.bounds.height > 1
        else { return nil }
        window.appearance = appearance
        let wasVisible = window.isVisible
        if !wasVisible { window.orderFront(nil) }
        defer { if !wasVisible { window.orderOut(nil) } }
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        var output: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance {
            output = ImeAppearance.opaqueSnapshot(rep, background: .windowBackgroundColor)
        }
        return output
    }

    /// 只刷新发生变化的行，避免打断其它行的编辑。
    func configChanged(_ key: String) {
        rows.first { $0.option.key == key }?.reload()
        if key == "appearance.theme", let window { ImeAppearance.applyTheme(to: window) }
        if key == "*error" {
            setStatus(ImeConfig.errorMessage() ?? "", isError: ImeConfig.errorMessage() != nil)
        }
    }

    /// 写失败提示（校验/IO/只读/锁）。
    func reportFailure(_ key: String) {
        setStatus("保存失败：\(ImeConfig.errorMessage() ?? key)", isError: true)
    }

    func windowWillClose(_ notification: Notification) {
        setStatus("", isError: false)
        // 关闭即释放整棵视图树与行引用，避免面板控件长期驻留（MEM-1）。
        // 下次 show() 会重新 prepare() 构建。
        window = nil
        rows.removeAll()
        sectionViews.removeAll()
        contentHost = nil
        segmented = nil
        statusLabel = nil
        session = nil
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = isError ? ImeAppearance.errorText : ImeAppearance.secondaryText
    }

    // MARK: - 分区切换

    @objc private func sectionChanged(_ sender: NSSegmentedControl) {
        selectSection(sender.selectedSegment)
    }

    private func selectSection(_ index: Int) {
        guard let host = contentHost, sectionViews.indices.contains(index) else { return }
        host.subviews.forEach { $0.removeFromSuperview() }
        let view = sectionViews[index]
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        segmented?.selectedSegment = index
    }

    // MARK: - 词库 动作

    @objc private func addWord() {
        guard let session else { return }
        if UserDictionaryUI.add(session) { setStatus("词条已添加。", isError: false) }
    }
    @objc private func removeWord() {
        guard let session else { return }
        if UserDictionaryUI.remove(session) { setStatus("用户词条及学习记录已删除；内置词不受影响。", isError: false) }
    }
    @objc private func importWords() {
        guard let session else { return }
        if let url = UserDictionaryUI.importFile(session) {
            setStatus("用户词库已导入：\(url.path)", isError: false)
        }
    }
    @objc private func exportWords() {
        guard let session else { return }
        if let url = UserDictionaryUI.exportFile(session) {
            setStatus("用户词库已导出：\(url.path)", isError: false)
        }
    }
    @objc private func lookupPinyin() {
        guard let session else { return }
        LookupUI.show(session)
    }

    // MARK: - 构建

    private func buildContent(_ panel: NSPanel) {
        let segmented = NSSegmentedControl(
            labels: Section.allCases.map(\.title),
            trackingMode: .selectOne, target: self, action: #selector(sectionChanged(_:)))
        segmented.selectedSegment = Section.settings.rawValue
        segmented.translatesAutoresizingMaskIntoConstraints = false
        self.segmented = segmented

        let host = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        contentHost = host

        let status = NSTextField(wrappingLabelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = ImeAppearance.secondaryText
        status.lineBreakMode = .byWordWrapping
        status.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = status

        sectionViews = [
            buildSettingsSection(),
            buildDictionarySection(),
        ]

        let content = panel.contentView!
        content.addSubview(segmented)
        content.addSubview(host)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            segmented.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            segmented.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            host.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            host.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        selectSection(Section.settings.rawValue)
    }

    /// 设置分区：Schema 驱动的滚动列表。
    private func buildSettingsSection() -> NSView {
        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 14
        rowStack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let options = SettingsSchema.options()
        for scope in Set(options.map(\.scope)).sorted() {
            let group = options.filter { $0.scope == scope }
            guard let first = group.first else { continue }
            let header = NSTextField(labelWithString: first.scopeTitle)
            header.font = .boldSystemFont(ofSize: 13)
            header.textColor = .labelColor
            rowStack.addArrangedSubview(header)
            for option in group {
                let row = SettingRow(option: option)
                rows.append(row)
                rowStack.addArrangedSubview(row)
                row.widthAnchor.constraint(equalTo: rowStack.widthAnchor, constant: -36).isActive = true
            }
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: document.topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
        return scroll
    }

    /// 词库分区：用户词库增/导/出与拼音反查（依赖当前会话，故按需传入）。
    private func buildDictionarySection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10

        let intro = NSTextField(
            wrappingLabelWithString: "用户词库只存本地，可新增、精确删除、导入和导出；纠错时先删除再添加。")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = ImeAppearance.secondaryText
        intro.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(intro)
        stack.setCustomSpacing(16, after: intro)

        for (title, action) in [
            ("新增词条…", #selector(addWord)),
            ("删除用户词条…", #selector(removeWord)),
            ("导入用户词库…", #selector(importWords)),
            ("导出用户词库…", #selector(exportWords)),
            ("拼音反查…", #selector(lookupPinyin)),
        ] as [(String, Selector)] {
            let button = NSButton(title: title, target: self, action: action)
            stack.addArrangedSubview(button)
        }
        return topAligned(stack)
    }

    /// 把内容顶部对齐放进一个填充分区的容器（其余留白）。
    private func topAligned(_ view: NSView) -> NSView {
        let container = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            view.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -18),
        ])
        return container
    }
}

/// 让滚动内容从顶部开始排布的翻转视图。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
