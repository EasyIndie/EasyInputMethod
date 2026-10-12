// Bounded test helper: operate only on owned sources and the recorded original source.
import Carbon
import Darwin
import Foundation

func fail(_ message: String) -> Never {
    fputs("BLOCKED：\(message)\n", stderr)
    exit(3)
}
func property(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
}
func identifier(_ source: TISInputSource) -> String {
    property(source, kTISPropertyInputSourceID) as? String ?? ""
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, ["state", "register", "disable-owned", "select-owned", "restore-original"].contains(args[0]) else { fail("参数不符") }
let root = URL(fileURLWithPath: args[1]).standardizedFileURL
let prefix = "lampyris-imk-"
let suffix = String(root.lastPathComponent.dropFirst(prefix.count))
let identity = "cn.jokerhub.inputmethod.LampyrisIMKTest.\(suffix)"
let fm = FileManager.default
guard root.lastPathComponent.hasPrefix(prefix), UUID(uuidString: suffix) != nil,
      (try? String(contentsOf: root.appendingPathComponent("owner"), encoding: .utf8)) == root.lastPathComponent,
      let attributes = try? fm.attributesOfItem(atPath: root.path),
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700
else { fail("独有目录身份不符") }
let ownedIDs = Set([identity, identity + ".default"])
func sources() -> [TISInputSource] {
    TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource]
}
func current() -> String { identifier(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) }
func owned() -> [TISInputSource] {
    sources().filter { ownedIDs.contains(identifier($0)) && property($0, kTISPropertyBundleID) as? String == identity }
}
guard !current().isEmpty else { fail("无法读取原输入源精确ID") }

if args[0] == "register" {
    guard owned().isEmpty else { fail("测试身份已存在，拒绝复用") }
    let app = root.appendingPathComponent("LampyrisIMKTest.app")
    let alias = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Input Methods/LampyrisIMKTest-\(suffix).app")
    guard let aliasAttributes = try? fm.attributesOfItem(atPath: alias.path),
          ([FileAttributeType.typeSymbolicLink, .typeDirectory].contains(aliasAttributes[.type] as? FileAttributeType ?? .typeUnknown)),
          (alias.resolvingSymlinksInPath().path == app.path ||
           (aliasAttributes[.type] as? FileAttributeType == .typeDirectory &&
            (try? String(contentsOf: alias.appendingPathComponent("Contents/Resources/IMKTestRoot"), encoding: .utf8)).map { URL(fileURLWithPath: $0).standardizedFileURL.path } == root.path)),
          Bundle(url: alias)?.bundleIdentifier == identity
    else { fail("注册软链或包身份不符") }
    let status = TISRegisterInputSource(alias as CFURL)
    guard status == noErr, !owned().isEmpty else { fail("注册失败（\(status)）或没有独有输入源") }
}
if ["select-owned", "restore-original"].contains(args[0]) {
    let journal = root.appendingPathComponent("selection-state.json")
    guard let attributes = try? fm.attributesOfItem(atPath: journal.path),
          attributes[.type] as? FileAttributeType == .typeRegular,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
          (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
          let data = try? Data(contentsOf: journal),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          value["identity"] as? String == identity,
          let original = value["current"] as? String, !original.isEmpty, !ownedIDs.contains(original)
    else { fail("原输入源日志身份或权限不符") }
    let selected = current()
    if args[0] == "select-owned" {
        guard selected == original,
              let mode = owned().first(where: { identifier($0) == identity + ".default" })
        else { fail("当前输入源已变或独有模式不存在，不选择") }
        guard let parent = owned().first(where: { identifier($0) == identity }),
              (property(parent, kTISPropertyInputSourceIsEnabled) as? Bool == true ||
               TISEnableInputSource(parent) == noErr) else { fail("启用独有父输入源失败") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let refreshedMode = owned().first(where: { identifier($0) == identity + ".default" }),
              (property(refreshedMode, kTISPropertyInputSourceIsEnabled) as? Bool == true ||
               TISEnableInputSource(refreshedMode) == noErr) else { fail("启用独有模式失败") }
        guard let refreshed = owned().first(where: { identifier($0) == identifier(mode) }) else { fail("启用后独有模式不存在") }
        let status = TISSelectInputSource(refreshed)
        let deadline = Date().addingTimeInterval(2)
        while status == noErr && current() != identity + ".default" && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard status == noErr, current() == identity + ".default"
        else { fail("选择独有模式失败：状态\(status)，当前\(current())，预期\(identity).default，父启用\(String(describing: property(parent, kTISPropertyInputSourceIsEnabled)))，可选\(String(describing: property(refreshed, kTISPropertyInputSourceIsSelectCapable)))，启用\(String(describing: property(refreshed, kTISPropertyInputSourceIsEnabled)))") }
    } else if selected != original {
        guard selected == identity + ".default",
              let source = sources().first(where: { identifier($0) == original }),
              property(source, kTISPropertyInputSourceIsEnabled) as? Bool == true,
              TISSelectInputSource(source) == noErr, current() == original
        else { fail("输入源已被用户改变或原源不可恢复，不覆盖") }
    }
}
if args[0] == "disable-owned" {
    guard !ownedIDs.contains(current()) else { fail("独有输入源正在使用；拒绝隐式切换") }
    let list = owned().sorted { identifier($0).hasSuffix(".default") && !identifier($1).hasSuffix(".default") }
    for source in list {
        if property(source, kTISPropertyInputSourceIsEnabled) as? Bool == true {
            guard TISDisableInputSource(source) == noErr else { fail("禁用独有输入源失败") }
        }
    }
}
let enabled = sources().filter { property($0, kTISPropertyInputSourceIsEnabled) as? Bool == true }.map(identifier).sorted()
let result: [String: Any] = ["current": current(), "enabled": enabled,
    "owned": owned().map { ["id": identifier($0), "label": property($0, kTISPropertyLocalizedName) as? String ?? "", "enabled": property($0, kTISPropertyInputSourceIsEnabled) as? Bool ?? false,
        "enableCapable": property($0, kTISPropertyInputSourceIsEnableCapable) as? Bool ?? false,
        "selectCapable": property($0, kTISPropertyInputSourceIsSelectCapable) as? Bool ?? false,
        "type": property($0, kTISPropertyInputSourceType) as? String ?? ""] }]
guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
      let text = String(data: data, encoding: .utf8) else { fail("无法记录输入源状态") }
print(text)
