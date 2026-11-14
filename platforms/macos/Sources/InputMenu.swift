import AppKit
import InputMethodKit

/// Current values, rebuilt from the session and the shared configuration snapshot.
struct InputMenuState {
    let mode: String
    let language: String
    let width: String
    let variant: String
    let punctuation: String
    let enabled: Bool
}

/// 更新入口：优先启动独立更新程序，否则打开 Release 页面。宿主本身不联网。
enum UpdateEntry {
    static let releasePage = URL(string: "https://github.com/EasyIndie/EasyInputMethod/releases/latest")!
    static let updaterBundleID = "cn.jokerhub.Lampyris.WebsiteUpdateCheck"
    /// 正式包名（ADR-294）。目录名不是判据，只用于在两个候选里挑更规范的那个。
    static let updaterBundleName = "LampyrisUpdateCheck.app"

    /// 先按安装位置找（`~/Applications` → `/Applications`），LaunchServices 注册只作兜底。
    static var installDirectories: [URL] {
        [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
         URL(fileURLWithPath: "/Applications")]
    }

    /// 在一个目录里按 bundle id 认更新程序；历史遗留的 `Lampyris Update.app` 同样能被认出来。
    static func updater(in directory: URL) -> URL? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return nil }
        let candidates = children
            .filter { $0.pathExtension == "app" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .filter { Bundle(url: $0)?.bundleIdentifier == updaterBundleID }
        return candidates.first { $0.lastPathComponent == updaterBundleName } ?? candidates.first
    }

    /// 更新程序定位：**先查安装位置，LaunchServices 只作兜底**。
    ///
    /// 反过来的顺序会让 LaunchServices 里残留的副本胜出——用户从 DMG/下载目录打开过一次，
    /// 那份旧包（甚至已删除的路径）就会抢在 `~/Applications` 的新版前面，菜单点了打开旧更新
    /// 程序或干脆没反应（报告 213 P2）。
    static func resolve(directories: [URL], registered: URL?) -> URL? {
        for directory in directories {
            if let found = updater(in: directory) { return found }
        }
        if let registered, Bundle(url: registered)?.bundleIdentifier == updaterBundleID {
            return registered
        }
        return nil
    }

    static func updaterURL() -> URL? {
        resolve(directories: installDirectories,
                registered: NSWorkspace.shared.urlForApplication(withBundleIdentifier: updaterBundleID))
    }

    static func open() {
        if let app = updaterURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.arguments = ["--ui"]
            NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else {
            NSWorkspace.shared.open(releasePage)
        }
    }
}

/// 动作区条目与**固定顺序**（ADR-360）。
///
/// 状态区 5 行由 IMK 契约固定在最前；动作区分两组：
/// 1. 学习与工具：学习区开关 → 练习 → 符号与表情 → 使用指南；
/// 2. 应用：检查更新 → 设置 → 关于。
///
/// 新增入口只能追加到所属组末尾并更新 `input-menu.swift` 探针，不允许打乱既有相对顺序；
/// 异常状态恒在最后且仅在出错时出现。
enum InputMenuAction: Int, CaseIterable {
    case toggleLearning = 10
    case practice = 11
    case symbols = 12
    case guide = 13
    case update = 14
    case settings = 15
    case about = 16

    /// 组内顺序；空分隔线只加在两组之间。
    static let sections: [[InputMenuAction]] = [
        [.toggleLearning, .practice, .symbols, .guide],
        [.update, .settings, .about],
    ]

    static var ordered: [InputMenuAction] { sections.flatMap { $0 } }

    var title: String {
        switch self {
        case .toggleLearning: return "显示学习区"
        case .practice: return "练习…"
        case .symbols: return "符号与表情…"
        case .guide: return "使用指南…"
        case .update: return "检查更新…"
        case .settings: return "设置…"
        case .about: return "关于"
        }
    }

    /// 与菜单项快捷键提示同源的配置键；`nil` 表示无快捷键。
    var hotkeyKey: String? {
        switch self {
        case .toggleLearning: return "hotkey.toggle_wubi_learning"
        case .practice: return "hotkey.open_practice"
        case .symbols: return "hotkey.open_symbols"
        case .guide: return nil
        case .update: return "hotkey.open_update"
        case .settings: return "hotkey.open_settings"
        case .about: return "hotkey.open_about"
        }
    }
}

/// Public AppKit menu contract; callbacks also accept IMK command dictionaries.
enum InputStateMenu {
    enum Command: Int {
        case cycleMode = 1, toggleEnglish, toggleWidth, toggleVariant, togglePunctuation
    }

    static let action = NSSelectorFromString("performInputMenuCommand:")
    static let modes = [("mixed", "混输"), ("wubi", "五笔"), ("pinyin", "拼音")]
    static let shortcuts = ["hotkey.toggle_mode", "hotkey.toggle_english", "hotkey.toggle_width",
                            "hotkey.toggle_variant", "hotkey.toggle_punctuation"]

    static func make(state: InputMenuState, target: AnyObject) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let commands: [Command] = [.cycleMode, .toggleEnglish, .toggleWidth, .toggleVariant, .togglePunctuation]
        for command in commands {
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            item.tag = command.rawValue
            item.target = target
            menu.addItem(item)
        }
        refresh(menu, state: state)
        return menu
    }

    static func command(from sender: Any?) -> Command? {
        let item: NSMenuItem?
        if let direct = sender as? NSMenuItem {
            item = direct
        } else {
            item = (sender as? [AnyHashable: Any])?[kIMKCommandMenuItemName as String] as? NSMenuItem
        }
        guard let item, item.isEnabled, item.action == action else { return nil }
        return Command(rawValue: item.tag)
    }

    static func nextMode(_ current: String) -> String {
        let index = modes.firstIndex(where: { $0.0 == current }) ?? 0
        return modes[(index + 1) % modes.count].0
    }

    static func refresh(_ menu: NSMenu, state: InputMenuState) {
        guard menu.items.count >= 5 else { return }
        let mode = modes.first(where: { $0.0 == state.mode })?.1 ?? "混输"
        let titles = [mode + "模式", state.language + "输入", state.width + "输入",
                      state.variant + "输入", state.punctuation]
        for (item, title) in zip(menu.items.prefix(5), titles) {
            item.title = title
            item.state = .off
            item.isEnabled = state.enabled
        }
        let modeItem = menu.items[0]
        // Mode cycling persists through ime-config even before IMK activates a session.
        modeItem.isEnabled = true
        modeItem.setAccessibilityValue(mode)
        modeItem.toolTip = nil
    }
}
