// 偏好设置面板（ADR-070）：完全由 `ime_config_schema()` 驱动，界面零硬编码。
//
// 非模态、改动即时生效：写入只经 `ime_config_set()`（配置唯一写入路径），
// 变更广播由 `ConfigWatcher` 派发（ADR-058）。见 `docs/配置架构.md` §8/§9/§11。

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
        if let control = buildControl() { top.addArrangedSubview(control) }

        let help = NSTextField(wrappingLabelWithString: option.doc)
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor
        help.preferredMaxLayoutWidth = 430

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
final class SettingsPanel: NSObject, NSWindowDelegate {
    static let shared = SettingsPanel()
    private var window: NSPanel?
    private var rows: [SettingRow] = []
    private var statusLabel: NSTextField?

    private override init() { super.init() }

    /// 构建窗口（幂等，不前置）；供 `show()` 与冒烟测试复用。
    func prepare() {
        guard window == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false)
        panel.title = "萤火虫 · 偏好设置"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        buildContent(panel)
        panel.center()
        window = panel
        // 其它入口（快捷键/菜单/外部编辑）改配置时，保持面板控件同步。
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in self?.configChanged(key) }
    }

    func show() {
        prepare()
        rows.forEach { $0.reload() }
        statusLabel?.stringValue = ""
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 已构建的行数（供冒烟测试断言）。
    var rowCount: Int { rows.count }

    /// 只刷新发生变化的行，避免打断其它行的编辑。
    func configChanged(_ key: String) {
        rows.first { $0.option.key == key }?.reload()
    }

    /// 写失败提示（校验/IO/只读/锁）。
    func reportFailure(_ key: String) {
        statusLabel?.stringValue = "保存失败：\(key)（配置可能只读或文件被锁定）"
    }

    @objc private func closePanel() {
        window?.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        statusLabel?.stringValue = ""
    }

    private func buildContent(_ panel: NSPanel) {
        let rowStack = NSStackView()
        rowStack.orientation = .vertical
        rowStack.alignment = .leading
        rowStack.spacing = 14
        rowStack.edgeInsets = NSEdgeInsets(top: 16, left: 18, bottom: 16, right: 18)
        rowStack.translatesAutoresizingMaskIntoConstraints = false

        var lastScope: Int?
        for option in SettingsSchema.options() {
            if option.scope != lastScope {
                lastScope = option.scope
                let header = NSTextField(labelWithString: option.scopeTitle)
                header.font = .boldSystemFont(ofSize: 13)
                header.textColor = .secondaryLabelColor
                rowStack.addArrangedSubview(header)
            }
            let row = SettingRow(option: option)
            rows.append(row)
            rowStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowStack.widthAnchor, constant: -36).isActive = true
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

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .systemRed
        status.translatesAutoresizingMaskIntoConstraints = false
        statusLabel = status

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(status)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        panel.contentView = content
    }
}

/// 让滚动内容从顶部开始排布的翻转视图。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
