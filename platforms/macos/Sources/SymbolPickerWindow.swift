import Cocoa

/// 符号 / emoji 选择面板（U3-5 / ADR-349）。
///
/// 独立、非模态、可关闭；数据全部来自随包 TSV，不联网。表格视图按需复用行，
/// 全量 emoji（约 3,800 条）不会一次性创建控件。插入通过回调交给宿主，不经过引擎。
final class SymbolPickerWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate,
    NSSearchFieldDelegate, NSWindowDelegate {
    static let shared = SymbolPickerWindow()

    private var panel: SymbolPanel?
    private var table: SymbolTable?
    private var search: SymbolSearchField?
    private var categoryPopup: NSPopUpButton?
    private var status: NSTextField?
    private var items: [PickerItem] = []
    private var categories: [SymbolCategory] = []
    private var currentCategory: SymbolCategory?
    private var onInsert: ((String) -> Void)?
    private var previousApp: NSRunningApplication?

    private let cellIdentifier = NSUserInterfaceItemIdentifier("SymbolPickerCell")

    /// 打开面板；`category` 为空时停留在上次分类。
    func show(onInsert: @escaping (String) -> Void, category: SymbolCategory? = nil) {
        prepare()
        self.onInsert = onInsert
        if let category, let index = categories.firstIndex(where: { $0.id == category.id }) {
            categoryPopup?.selectItem(at: index)
            currentCategory = categories[index]
        } else if currentCategory == nil {
            currentCategory = categories.first
            categoryPopup?.selectItem(at: 0)
        }
        search?.stringValue = ""
        reload()
        previousApp = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(search)
    }

    func showEmoji(onInsert: @escaping (String) -> Void) {
        show(onInsert: onInsert, category: SymbolCatalog.shared.emojiGroups.first)
    }

    func close() {
        panel?.orderOut(nil)
        restorePreviousApp()
    }

    private func restorePreviousApp() {
        previousApp?.activate(options: [])
        previousApp = nil
    }

    // MARK: - 构建

    private func prepare() {
        guard panel == nil else { return }
        categories = SymbolCatalog.shared.allCategories
        let panel = SymbolPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 440),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = "符号与 emoji — 萤火虫"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 480, height: 320)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.close() }
        ImeAppearance.applyTheme(to: panel)

        let popup = NSPopUpButton()
        popup.addItems(withTitles: categories.map(\.title))
        popup.target = self
        popup.action = #selector(categoryChanged(_:))
        popup.setAccessibilityLabel("分类")
        popup.widthAnchor.constraint(equalToConstant: 128).isActive = true
        categoryPopup = popup

        let search = SymbolSearchField()
        search.placeholderString = "搜索符号或 emoji（中文 / 英文）"
        search.delegate = self
        search.setAccessibilityLabel("搜索符号或 emoji")
        search.setAccessibilityHelp("输入中文或英文关键词过滤；结果可用方向键选择，回车插入。")
        search.onDown = { [weak self] in
            guard let self, let table = self.table else { return }
            self.panel?.makeFirstResponder(table)
            if table.selectedRow < 0, !self.items.isEmpty {
                table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }
        self.search = search

        let table = SymbolTable()
        table.headerView = nil
        table.rowHeight = 38
        table.allowsEmptySelection = false
        table.allowsMultipleSelection = false
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(insertSelected)
        table.setAccessibilityLabel("符号列表")
        table.onReturn = { [weak self] in self?.insertSelected() }
        self.table = table
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)

        let status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = ImeAppearance.secondaryText
        status.lineBreakMode = .byTruncatingTail
        status.setAccessibilityLabel("操作结果")
        self.status = status

        let top = NSStackView(views: [popup, search])
        top.orientation = .horizontal
        top.spacing = 10
        top.alignment = .centerY
        let content = NSStackView(views: [top, scroll, status])
        content.orientation = .vertical
        content.spacing = 8
        content.alignment = .leading
        content.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 10, right: 14)
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(content)
        guard let host = panel.contentView else { return }
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            top.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            scroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 180),
            status.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -28),
        ])
        panel.initialFirstResponder = search
        self.panel = panel
        currentCategory = categories.first
        popup.selectItem(at: 0)
    }

    // MARK: - 数据

    private func reload() {
        let query = search?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if query.isEmpty {
            items = currentCategory.map { SymbolCatalog.shared.items(in: $0) } ?? []
        } else {
            items = SymbolCatalog.shared.search(query)
        }
        table?.reloadData()
        if !items.isEmpty {
            table?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            table?.scrollRowToVisible(0)
        }
        let hint = query.isEmpty ? "共 \(items.count) 项" : "找到 \(items.count) 项"
        status?.stringValue = SymbolCatalog.shared.loadError ?? hint
    }

    @objc private func categoryChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard categories.indices.contains(index) else { return }
        currentCategory = categories[index]
        search?.stringValue = ""
        reload()
        panel?.makeFirstResponder(table)
    }

    @objc private func insertSelected() {
        let row = table?.selectedRow ?? -1
        guard items.indices.contains(row) else { return }
        let item = items[row]
        onInsert?(item.text)
        status?.stringValue = "已插入 \(item.text) \(item.name)"
        table?.scrollRowToVisible(row)
    }

    // MARK: - 表格

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard items.indices.contains(row) else { return nil }
        let item = items[row]
        let view: SymbolCellView
        if let reused = tableView.makeView(withIdentifier: cellIdentifier, owner: self)
            as? SymbolCellView {
            view = reused
        } else {
            view = SymbolCellView()
            view.identifier = cellIdentifier
        }
        view.configure(item)
        return view
    }

    // MARK: - 搜索

    func controlTextDidChange(_ obj: Notification) {
        reload()
    }

    // MARK: - 窗口

    func windowWillClose(_ notification: Notification) {
        restorePreviousApp()
    }

    // MARK: - 测试

    func prepareForTesting() { prepare() }
    var itemCountForTesting: Int { items.count }
    var currentItemsForTesting: [PickerItem] { items }
    func setSearchForTesting(_ text: String) {
        search?.stringValue = text
        reload()
    }
    func selectCategoryForTesting(_ id: String) -> Bool {
        guard let index = categories.firstIndex(where: { $0.id == id }) else { return false }
        categoryPopup?.selectItem(at: index)
        currentCategory = categories[index]
        reload()
        return true
    }
    func setInsertHandlerForTesting(_ handler: ((String) -> Void)?) { onInsert = handler }
    func insertFirstForTesting() -> String? {
        guard let first = items.first else { return nil }
        onInsert?(first.text)
        status?.stringValue = "已插入 \(first.text) \(first.name)"
        return first.text
    }
    var panelForTesting: NSPanel? { panel }
}

/// Esc 关闭；其余按键交给 AppKit。
private final class SymbolPanel: NSPanel {
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// 搜索框里按下箭头进入列表；Esc 关闭。
private final class SymbolSearchField: NSSearchField {
    var onDown: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 125 { onDown?(); return }
        if event.keyCode == 53 { window?.performClose(nil); return }
        super.keyDown(with: event)
    }
}

/// 列表里回车插入；Esc 关闭。
private final class SymbolTable: NSTableView {
    var onReturn: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?(); return }
        if event.keyCode == 53 { window?.performClose(nil); return }
        super.keyDown(with: event)
    }
}

/// 一行：大号符号 + 中文名 + 英文/关键词。
private final class SymbolCellView: NSTableCellView {
    private let symbol = NSTextField(labelWithString: "")
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        symbol.font = .systemFont(ofSize: 20)
        symbol.alignment = .center
        symbol.widthAnchor.constraint(equalToConstant: 40).isActive = true
        name.font = .systemFont(ofSize: 13)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = ImeAppearance.secondaryText
        detail.lineBreakMode = .byTruncatingTail
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [symbol, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: PickerItem) {
        symbol.stringValue = item.text
        name.stringValue = item.name
        detail.stringValue = item.detail
        setAccessibilityLabel(item.accessibilityLabel)
        setAccessibilityRole(.row)
    }
}
