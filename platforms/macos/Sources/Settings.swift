// 偏好设置面板（ADR-070 / ADR-075）：由 `ime_config_schema()` 驱动，界面零硬编码。
//
// 非模态、改动即时生效：写入只经 `ime_config_set()`（配置唯一写入路径），
// 变更广播由 `ConfigWatcher` 派发（ADR-058）。见 `docs/配置架构.md` §8/§9/§11。
//
// ADR-166: Native input/candidates/shortcuts/dictionary preference panes.
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

    /// Hide implementation comparison notes while preserving schema-defined guidance.
    var userHelp: String {
        doc.replacingOccurrences(of: #"(?:，|,)?对齐[^）)]*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "（）", with: "")
            .replacingOccurrences(of: "()", with: "")
    }

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
    private var segmented: NSSegmentedControl?
    private var shortcutButton: NSButton?
    private var stepper: NSStepper?
    private var numberLabel: NSTextField?
    private var textField: NSTextField?
    private var rawValues: [String] = []

    init(option: SettingsOption) {
        self.option = option
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 6

        let title = NSTextField(labelWithString: option.title)
        title.font = .systemFont(ofSize: 13)
        title.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let top = NSStackView()
        top.orientation = .horizontal
        top.alignment = .centerY
        top.heightAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        top.spacing = 10
        let isBoolean: Bool
        if case .bool = option.kind { isBoolean = true } else { isBoolean = false }
        if !isBoolean { top.addArrangedSubview(title); top.addArrangedSubview(NSView()) }
        if let control = buildControl() {
            control.setAccessibilityLabel(option.title)
            control.setAccessibilityHelp(option.userHelp)
            top.addArrangedSubview(control)
        }
        if isBoolean { top.addArrangedSubview(NSView()) }
        addArrangedSubview(top)
        let visibleHelp = ["mode", "input.full_width", "pinyin.fuzzy", "candidate.show_wubi_learning"]
        if visibleHelp.contains(option.key) {
            let help = NSTextField(wrappingLabelWithString: option.userHelp)
            help.font = .systemFont(ofSize: 11)
            help.textColor = ImeAppearance.secondaryText
            help.lineBreakMode = .byWordWrapping
            addArrangedSubview(help)
            help.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        top.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }

    required init?(coder: NSCoder) { nil }

    /// 按 Schema 类型构建控件；返回应加入标题行的视图。
    private func buildControl() -> NSView? {
        switch option.kind {
        case .bool:
            let box = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(boolChanged(_:)))
            checkbox = box
            return box
        case .int(let min, let max):
            let value = NSTextField()
            value.bezelStyle = .roundedBezel
            value.delegate = self
            value.target = self
            value.action = #selector(numberCommitted(_:))
            value.setAccessibilityLabel(option.title)
            value.setAccessibilityHelp(option.userHelp)
            value.alignment = .right
            value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
            value.widthAnchor.constraint(equalToConstant: 54).isActive = true
            numberLabel = value
            let stepper = NSStepper()
            stepper.minValue = Double(min)
            stepper.maxValue = Double(max)
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.target = self
            stepper.action = #selector(stepperChanged(_:))
            stepper.setAccessibilityLabel(option.title)
            stepper.setAccessibilityHelp(option.userHelp)
            self.stepper = stepper
            let box = NSStackView(views: [value, stepper])
            box.orientation = .horizontal
            box.spacing = 6
            box.alignment = .centerY
            return box
        case .choice(let values, let labels):
            rawValues = values
            if option.key == "mode" {
                let control = NSSegmentedControl(labels: labels, trackingMode: .selectOne,
                    target: self, action: #selector(segmentChanged(_:)))
                control.widthAnchor.constraint(equalToConstant: 244).isActive = true
                segmented = control
                return control
            }
            let menu = NSPopUpButton()
            menu.widthAnchor.constraint(equalToConstant: 148).isActive = true
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
            let button = NSButton(title: "", target: self, action: #selector(editShortcut(_:)))
            button.bezelStyle = .rounded
            button.widthAnchor.constraint(equalToConstant: 130).isActive = true
            shortcutButton = button
            return button
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
            if let index = values.firstIndex(of: raw) { popup?.selectItem(at: index); segmented?.selectedSegment = index }
        case .text:
            textField?.stringValue = raw == "none" ? "" : raw
            let binding = ImeConfig.hotkey(option.key)
            let flags = binding.modifiers
            let symbols = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
                + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            let key = binding.key == 32 ? "空格" : binding.equivalent.uppercased()
            shortcutButton?.title = binding.kind == 0 ? "未设置" : binding.kind == 1 ? "⇧" : symbols + key
        }
    }

    var shortcutTitleForTesting: String? { shortcutButton?.title }
    var textValueForTesting: String? { textField?.stringValue }
    func commitTextForTesting(_ value: String) -> Bool {
        guard let field = textField, let action = field.action else { return false }
        field.stringValue = value
        return NSApp.sendAction(action, to: field.target, from: field)
    }

    // MARK: - 写回（唯一路径）

    @objc private func boolChanged(_ sender: NSButton) {
        write(sender.state == .on ? "true" : "false", toml: true)
    }

    @objc private func numberCommitted(_ sender: NSTextField) {
        write(sender.stringValue.trimmingCharacters(in: .whitespaces), toml: true)
        reload()
    }

    var numberValueForTesting: String? { numberLabel?.stringValue }
    func commitNumberForTesting(_ value: String) {
        guard let field = numberLabel else { return }
        field.stringValue = value
        numberCommitted(field)
    }

    @objc private func stepperChanged(_ sender: NSStepper) {
        write(String(sender.integerValue), toml: true)
    }

    @objc private func segmentChanged(_ sender: NSSegmentedControl) {
        guard rawValues.indices.contains(sender.selectedSegment) else { return }
        write(rawValues[sender.selectedSegment], toml: false)
    }

    @objc private func editShortcut(_ sender: NSButton) {
        presentShortcutEditor(textField?.stringValue ?? "", message: nil)
    }

    private func presentShortcutEditor(_ value: String, message: String?) {
        guard let host = window else { return }
        let alert = NSAlert()
        ImeAppearance.applyTheme(to: alert.window)
        alert.messageText = "修改\(option.title)"
        alert.informativeText = message ?? option.userHelp
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")
        let input = NSTextField(string: value)
        input.frame = NSRect(x: 0, y: 0, width: 360, height: 26)
        input.placeholderString = "如 ctrl+shift+k；留空关闭"
        input.setAccessibilityLabel(option.title)
        alert.accessoryView = input
        alert.window.initialFirstResponder = input
        alert.beginSheetModal(for: host) { [weak self, weak host] response in
            guard let self, let host, self.window === host, response == .alertFirstButtonReturn else { return }
            let value = input.stringValue.trimmingCharacters(in: .whitespaces)
            if ImeConfig.setString(self.option.key, value.isEmpty ? "none" : value) {
                self.reload()
                SettingsPanel.shared.reportSaved()
            } else {
                let error = ImeConfig.errorMessage() ?? "无法保存，请检查绑定或配置文件权限。"
                SettingsPanel.shared.reportFailure(self.option.key)
                DispatchQueue.main.async { [weak self, weak host] in
                    guard let self, let host, self.window === host else { return }
                    self.presentShortcutEditor(value, message: "保存失败：" + error + " 输入已保留。")
                }
            }
        }
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
        guard let field = notification.object as? NSTextField else { return }
        if field === numberLabel { numberCommitted(field) }
        else if field === textField { textCommitted(field) }
    }

    private func write(_ value: String, toml: Bool) {
        let ok = toml ? ImeConfig.setToml(option.key, value) : ImeConfig.setString(option.key, value)
        if ok {
            SettingsPanel.shared.reportSaved()
        } else {
            SettingsPanel.shared.reportFailure(option.key)
            reload()
        }
    }
}

/// 设置面板（进程内单例；重复打开只前置已有窗口）。
///
/// Nonmodal settings window with native task-oriented preference panes.
final class SettingsPanel: NSObject, NSWindowDelegate, NSToolbarDelegate {
    static let shared = SettingsPanel()

    /// 分区。新增分区 = 加一个 case + 一个 builder（保持可扩展、菜单不再膨胀）。
    private enum Section: Int, CaseIterable {
        case input, candidates, shortcuts, dictionary
        var title: String {
            switch self {
            case .input: return "输入"
            case .candidates: return "候选"
            case .shortcuts: return "快捷键"
            case .dictionary: return "词库"
            }
        }
        var symbol: String {
            switch self {
            case .input: return "keyboard"
            case .candidates: return "text.bubble"
            case .shortcuts: return "command"
            case .dictionary: return "character.book.closed"
            }
        }
        var identifier: NSToolbarItem.Identifier { .init("lampyris.settings.\(rawValue)") }
    }

    private var window: NSPanel?
    private var rows: [SettingRow] = []
    private var statusLabel: NSTextField?
    private weak var session: ImeSession?
    private var navigation: NSToolbar?
    private var selectedSection = Section.input.rawValue
    private var dictionaryButtons: [NSButton] = []
    private var contentHost: NSView?
    private var sectionViews: [NSView] = []

    private override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }
    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }
    @objc private func displayOptionsChanged() {
        if let window { ImeAppearance.applyTheme(to: window) }
    }

    /// 构建窗口（幂等，不前置）；供 `show()` 与冒烟测试复用。
    func prepare() {
        guard window == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        panel.title = "输入 — 萤火虫"
        panel.toolbarStyle = .preference
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        panel.contentMinSize = NSSize(width: 560, height: 440)
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
        dictionaryButtons.forEach { $0.isEnabled = session != nil }
        if let window { ImeAppearance.applyTheme(to: window) }
        setStatus("", isError: false)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 已构建的行数（供冒烟测试断言）。
    var rowCount: Int { rows.count }
    func rowForTesting(_ key: String) -> SettingRow? { rows.first { $0.option.key == key } }
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
    func renderSnapshotForTesting(appearance: NSAppearance, includingChrome: Bool = false) -> NSBitmapImageRep? {
        prepare()
        rows.forEach { $0.reload() }
        guard let window, let view = window.contentView, view.bounds.width > 1,
            view.bounds.height > 1
        else { return nil }
        window.appearance = appearance
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        let snapshotView = includingChrome ? (view.superview ?? view) : view
        snapshotView.layoutSubtreeIfNeeded()
        guard let rep = snapshotView.bitmapImageRepForCachingDisplay(in: snapshotView.bounds) else { return nil }
        snapshotView.cacheDisplay(in: snapshotView.bounds, to: rep)
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

    func reportSaved() { setStatus("", isError: false) }

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
        navigation = nil
        dictionaryButtons.removeAll()
        statusLabel = nil
        session = nil
    }

    private func setStatus(_ text: String, isError: Bool) {
        statusLabel?.stringValue = text
        statusLabel?.textColor = isError ? ImeAppearance.errorText : ImeAppearance.secondaryText
        if !text.isEmpty, window?.isVisible == true, let statusLabel {
            NSAccessibility.post(element: statusLabel, notification: .valueChanged)
        }
    }

    // MARK: - 分区切换

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Section.allCases.map(\.identifier)
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let section = Section.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = section.title
        item.paletteLabel = section.title
        item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
        item.target = self
        item.action = #selector(sectionChanged(_:))
        item.tag = section.rawValue
        item.toolTip = "显示\(section.title)设置"
        return item
    }
    @objc private func sectionChanged(_ sender: NSToolbarItem) { selectSection(sender.tag) }

    func selectSectionForTesting(_ index: Int) { prepare(); selectSection(index) }
    var selectedSectionForTesting: Int { selectedSection }
    var visibleOptionKeysForTesting: [String] {
        guard sectionViews.indices.contains(selectedSection) else { return [] }
        return rows.filter { $0.isDescendant(of: sectionViews[selectedSection]) }.map { $0.option.key }
    }
    var isVisibleForTesting: Bool { window?.isVisible == true }
    var statusForTesting: String { statusLabel?.stringValue ?? "" }

    var navigationIsNativeForTesting: Bool {
        navigation?.isVisible == true && navigation?.allowsUserCustomization == false
            && navigation?.selectedItemIdentifier == Section(rawValue: selectedSection)?.identifier
    }
    var dictionaryActionsEnabledForTesting: Bool { dictionaryButtons.allSatisfy(\.isEnabled) }
    func bindSessionForTesting(_ value: ImeSession?) {
        session = value
        dictionaryButtons.forEach { $0.isEnabled = value != nil }
    }

    private func selectSection(_ index: Int) {
        guard let host = contentHost, sectionViews.indices.contains(index) else { return }
        if window?.isVisible == true { _ = window?.makeFirstResponder(nil) }
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
        selectedSection = index
        navigation?.selectedItemIdentifier = Section(rawValue: index)?.identifier
        window?.title = "\(Section(rawValue: index)?.title ?? "设置") — 萤火虫"
        window?.recalculateKeyViewLoop()
    }

    // MARK: - 词库 动作

    @objc private func addWord() { presentWordEntry(deleting: false) }
    @objc private func removeWord() { presentWordEntry(deleting: true) }
    private func presentWordEntry(deleting: Bool) {
        guard let session, let host = window else { return }
        UserDictionaryUI.presentEntry(session, deleting: deleting, on: host) { [weak self, weak host] saved in
            guard saved, let self, let host, self.window === host, host.isVisible else { return }
            self.setStatus(deleting ? "用户词条及学习记录已删除；内置词不受影响。" : "词条已添加。", isError: false)
        }
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
        let toolbar = NSToolbar(identifier: "lampyris.settings")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.isVisible = true
        panel.toolbar = toolbar
        navigation = toolbar

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
            buildSettingsSection(scopes: [0]),
            buildSettingsSection(scopes: [1, 2]),
            buildSettingsSection(scopes: [3]),
            buildDictionarySection(),
        ]

        let content = panel.contentView!
        content.addSubview(host)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            host.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            host.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            host.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
        selectSection(selectedSection)
        panel.title = "\(Section(rawValue: selectedSection)?.title ?? "设置") — 萤火虫"
    }

    /// 设置分区：Schema 驱动的滚动列表。
    private func buildSettingsSection(scopes: [Int]) -> NSView {
        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 14
        rowStack.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 18, right: 12)
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        let options = SettingsSchema.options().filter { scopes.contains($0.scope) }
        let groups: [(String, [String])]
        if scopes == [0] {
            groups = [("默认输入", ["mode", "input.chinese_variant", "input.punctuation", "input.full_width"]),
                ("五笔与拼音", ["wubi.auto_commit", "wubi.z_key", "pinyin.fuzzy"])]
        } else if scopes.contains(3) {
            groups = [("快捷键", ["hotkey.toggle_mode", "hotkey.toggle_english", "hotkey.toggle_width",
                "hotkey.toggle_punctuation", "hotkey.toggle_variant", "hotkey.toggle_wubi_learning"])]
        } else {
            groups = [("候选显示", ["candidate.count", "candidate.page_with_comma"]),
                ("外观", ["appearance.theme"]), ("五笔学习", ["candidate.show_wubi_learning"])]
        }
        let known = Set(groups.flatMap { $0.1 })
        let allGroups = groups + [("其他", options.filter { !known.contains($0.key) }.map(\.key))]
        var count = 0
        for (title, keys) in allGroups {
            let group = keys.compactMap { key in options.first { $0.key == key } }
            guard !group.isEmpty else { continue }
            if count > 0 {
                let separator = NSBox(); separator.boxType = .separator
                rowStack.addArrangedSubview(separator)
                separator.widthAnchor.constraint(equalTo: rowStack.widthAnchor, constant: -24).isActive = true
            }
            count += 1
            let header = NSTextField(labelWithString: title)
            header.font = .systemFont(ofSize: 13, weight: .semibold)
            rowStack.addArrangedSubview(header)
            for option in group {
                let row = SettingRow(option: option)
                rows.append(row)
                let inset = NSView(); inset.widthAnchor.constraint(equalToConstant: 18).isActive = true
                let wrapper = NSStackView(views: [inset, row])
                wrapper.orientation = .horizontal
                wrapper.spacing = 0
                rowStack.addArrangedSubview(wrapper)
                wrapper.widthAnchor.constraint(equalTo: rowStack.widthAnchor, constant: -36).isActive = true
                row.widthAnchor.constraint(equalTo: wrapper.widthAnchor, constant: -18).isActive = true
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
            ("新增词条", #selector(addWord)),
            ("删除用户词条", #selector(removeWord)),
            ("导入用户词库", #selector(importWords)),
            ("导出用户词库", #selector(exportWords)),
            ("拼音反查", #selector(lookupPinyin)),
        ] as [(String, Selector)] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.isEnabled = session != nil
            button.setAccessibilityHelp("仅在本地操作用户词库；需要当前输入会话。")
            dictionaryButtons.append(button)
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
