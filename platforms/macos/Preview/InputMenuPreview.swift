import AppKit
import ime

/// Connect the production menu to a real session initialized in the owned preview root.
final class PreviewInputMenu: NSObject, NSMenuDelegate {
    let session: ImeSession
    var onCancelComposition: (() -> Void)?
    var onChange: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var onClose: (() -> Void)?
    var onSettings: (() -> Void)?
    var onAbout: (() -> Void)?
    lazy var menu: NSMenu = makeMenu()

    init(session: ImeSession) {
        self.session = session
        super.init()
        ConfigWatcher.shared.observe(owner: self) { [weak self] key in self?.configurationChanged(key) }
    }

    deinit { ConfigWatcher.shared.clear(owner: self) }

    private var state: InputMenuState {
        let variant = session.variantError != IME_OK ? "简体（繁体数据异常）" : session.isTraditional ? "繁体" : "简体"
        return InputMenuState(mode: session.mode, language: session.isEnglish ? "英文" : "中文",
            width: session.isFullWidth ? "全角" : "半角", variant: variant,
            punctuation: ImeConfig.string("input.punctuation") == "chinese" ? "中文标点" : "英文标点",
            enabled: true)
    }

    private func makeMenu() -> NSMenu {
        let result = InputStateMenu.make(state: state, target: self)
        result.delegate = self
        result.addItem(.separator())
        for (title, action) in [("设置", #selector(showSettings(_:))), ("关于", #selector(showAbout(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            result.addItem(item)
        }
        return result
    }

    func refresh() {
        for (item, key) in zip(menu.items.prefix(5), InputStateMenu.shortcuts) {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            let binding = ImeConfig.hotkey(key)
            if !item.applyConfiguredHotkey(binding), let symbol = NSMenuItem.singleModifierSymbol(binding) {
                item.keyEquivalent = symbol
                item.keyEquivalentModifierMask = []
            }
        }
        InputStateMenu.refresh(menu, state: state)
    }

    func menuWillOpen(_ menu: NSMenu) { refresh() }
    func menuDidClose(_ menu: NSMenu) { onClose?() }

    private func configurationChanged(_ key: String) {
        session.prepare()
        if let mode = ImeConfig.string("mode"), session.mode != mode {
            onCancelComposition?()
            session.setMode(mode)
        }
        if let count = ImeConfig.int("candidate.count") { session.setPageSize(count) }
        refresh()
        onChange?()
        if key == "*error", let message = ImeConfig.errorMessage() { onFailure?(message) }
    }

    private func changed(_ success: Bool = true) {
        refresh()
        onChange?()
        if !success { onFailure?(ImeConfig.errorMessage() ?? "设置未保存，请检查配置文件权限。") }
    }

    func selectMode(_ mode: String) {
        guard InputStateMenu.modes.contains(where: { $0.0 == mode }) else { return }
        if ImeConfig.string("mode") != mode, !ImeConfig.setString("mode", mode) { changed(false); return }
        if session.mode != mode {
            onCancelComposition?()
            session.setMode(mode)
        }
        changed()
    }

    @objc func performInputMenuCommand(_ sender: Any?) {
        guard let command = InputStateMenu.command(from: sender) else { return }
        switch command {
        case .cycleMode: selectMode(InputStateMenu.nextMode(session.mode))
        case .toggleEnglish: toggleEnglish(sender)
        case .toggleWidth: toggleWidth(sender)
        case .toggleVariant: toggleVariant(sender)
        case .togglePunctuation: togglePunctuation(sender)
        }
    }
    @objc func toggleEnglish(_ sender: Any?) { session.toggleEnglish(); changed() }
    @objc func toggleWidth(_ sender: Any?) { session.toggleWidth(); changed() }
    @objc func toggleVariant(_ sender: Any?) { changed(session.toggleVariant()) }
    @objc func togglePunctuation(_ sender: Any?) { changed(session.togglePunctuation()) }
    @objc private func showSettings(_ sender: Any?) { onSettings?() }
    @objc private func showAbout(_ sender: Any?) { onAbout?() }
}
