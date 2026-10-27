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

    /// 用户可放置更新程序的两个目录；查找不依赖子目录名字。
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

    static func updaterURL() -> URL? {
        if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: updaterBundleID),
           Bundle(url: registered)?.bundleIdentifier == updaterBundleID {
            return registered
        }
        for directory in installDirectories {
            if let found = updater(in: directory) { return found }
        }
        return nil
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
