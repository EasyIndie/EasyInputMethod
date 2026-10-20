// Dedicated test entry. Never compiled by the production Sources/*.swift build.
import Cocoa
import Carbon
import Darwin
import InputMethodKit
import ime

func blocked(_ message: String) -> Never {
    fputs("BLOCKED：\(message)\n", stderr)
    exit(3)
}

let fm = FileManager.default
guard let resources = Bundle.main.resourceURL else { blocked("缺少验收包资源目录") }
let canonicalResources = resources.resolvingSymlinksInPath()
let binding = canonicalResources.appendingPathComponent("IMKTestRoot")
guard let bindingAttributes = try? fm.attributesOfItem(atPath: binding.path),
      bindingAttributes[.type] as? FileAttributeType == .typeRegular,
      (bindingAttributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
      (bindingAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
      let rootPath = try? String(contentsOf: binding, encoding: .utf8)
else { blocked("测试根声明不符") }
let root = URL(fileURLWithPath: rootPath).standardizedFileURL
let prefix = "lampyris-imk-"
let suffix = String(root.lastPathComponent.dropFirst(prefix.count))
let canonicalApp = canonicalResources.deletingLastPathComponent().deletingLastPathComponent()
// 仅测试入口：私有根内存在 perf-trace.enabled 时，文件内容即计时输出路径（ADR-218）。
let traceMarker = root.appendingPathComponent("perf-trace.enabled")
if let tracePath = try? String(contentsOf: traceMarker, encoding: .utf8) {
    PerfTrace.configureForTest(tracePath: tracePath.trimmingCharacters(in: .whitespacesAndNewlines))
}
let installed = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Input Methods/LampyrisIMKTest-\(suffix).app")
guard root.path == root.resolvingSymlinksInPath().path,
      root.deletingLastPathComponent().path == URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath().path,
      root.lastPathComponent.hasPrefix(prefix), UUID(uuidString: suffix) != nil,
      [root.appendingPathComponent("LampyrisIMKTest.app").path, installed.path].contains(canonicalApp.path),
      Bundle.main.bundleIdentifier == "cn.jokerhub.inputmethod.LampyrisIMKTest.\(suffix.lowercased())"
else { blocked("验收目录或包身份不符") }

func validateOwned(_ path: URL, type: FileAttributeType) {
    guard let attributes = try? fm.attributesOfItem(atPath: path.path),
          attributes[.type] as? FileAttributeType == type,
          (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid(),
          let permissions = attributes[.posixPermissions] as? NSNumber,
          permissions.intValue & 0o077 == 0
    else { blocked("验收资源归属、类型或权限不符") }
}
validateOwned(root, type: .typeDirectory)
let marker = root.appendingPathComponent("owner")
validateOwned(marker, type: .typeRegular)
guard (try? String(contentsOf: marker, encoding: .utf8)) == root.lastPathComponent
else { blocked("验收所有权标记不符") }
for name in ["config.toml", "user-dictionary.tsv"] {
    let path = root.appendingPathComponent(name)
    if (try? fm.attributesOfItem(atPath: path.path)) != nil {
        validateOwned(path, type: .typeRegular)
    }
}
let args = Array(CommandLine.arguments.dropFirst())
let modes = ["normal", "failure", "INT", "TERM"]
guard args.isEmpty || (args.count == 2 && args[0] == "--isolation-probe" && modes.contains(args[1])) || (args.count == 2 && args[0] == "--source-action" && ["select", "restore"].contains(args[1]))
else { blocked("不支持的验收启动参数") }
guard ime_abi_version() == 1,
      root.appendingPathComponent("config.toml").path.withCString({ ime_config_init($0) }) == IME_OK
else { blocked("ABI或独立配置初始化失败") }

if args.first == "--source-action" {
    _ = NSApplication.shared
    let journal = root.appendingPathComponent("selection-state.json")
    validateOwned(journal, type: .typeRegular)
    guard let data = try? Data(contentsOf: journal),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let identity = Bundle.main.bundleIdentifier, value["identity"] as? String == identity,
          let original = value["current"] as? String, !original.isEmpty, !original.hasPrefix(identity)
    else { blocked("输入源日志不符") }
    func sourceProperty(_ source: TISInputSource, _ key: CFString) -> CFTypeRef? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFTypeRef>.fromOpaque(pointer).takeUnretainedValue()
    }
    func sourceID(_ source: TISInputSource) -> String { sourceProperty(source, kTISPropertyInputSourceID) as? String ?? "" }
    func sourceList() -> [TISInputSource] { TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource] }
    func selectedID() -> String { sourceID(TISCopyCurrentKeyboardInputSource().takeRetainedValue()) }
    if args[1] == "select" {
        guard selectedID() == original,
              let parent = sourceList().first(where: { sourceID($0) == identity }),
              sourceProperty(parent, kTISPropertyBundleID) as? String == identity,
              TISEnableInputSource(parent) == noErr else { blocked("父源启用失败或当前源已变") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let mode = sourceList().first(where: { sourceID($0) == identity + ".default" }),
              TISEnableInputSource(mode) == noErr else { blocked("模式启用失败") }
        let status = TISSelectInputSource(mode)
        guard status == noErr, selectedID() == identity + ".default" else {
            blocked("自身进程选择失败：状态\(status)，父启用\(String(describing: sourceProperty(parent, kTISPropertyInputSourceIsEnabled)))，当前\(selectedID())")
        }
    } else if selectedID() != original {
        guard selectedID() == identity + ".default",
              let source = sourceList().first(where: { sourceID($0) == original }),
              sourceProperty(source, kTISPropertyInputSourceIsEnabled) as? Bool == true,
              TISSelectInputSource(source) == noErr, selectedID() == original
        else { blocked("当前源已变或原源不可恢复，不覆盖") }
    }
    print("SOURCE " + selectedID())
    exit(0)
}

if !args.isEmpty {
    guard ImeConfig.setString("mode", "wubi"),
          let session = ImeSession(
            wubiPath: canonicalResources.appendingPathComponent("wubi86-core.tsv").path,
            pinyinCharsPath: canonicalResources.appendingPathComponent("pinyin-chars.tsv").path,
            pinyinWordsPath: canonicalResources.appendingPathComponent("pinyin-core.tsv").path),
          session.addWord(scheme: "wubi", code: "zz", text: "IMK隔离测试词") == IME_OK
    else { blocked("独立配置或测试词库写入失败") }
    session.setMode("wubi")
    for scalar in "zz".unicodeScalars { _ = session.feed(scalar.value) }
    guard session.candidates(limit: 9).contains(where: { $0.text == "IMK隔离测试词" })
    else { blocked("测试词未进入独立会话") }
    print("READY \(getpid())")
    fflush(stdout)
    let delay: TimeInterval = ["normal", "failure"].contains(args[1]) ? 0.5 : 3600
    let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
        exit(args[1] == "normal" ? 0 : 7)
    }
    withExtendedLifetime((session, timer)) { RunLoop.current.run() }
    blocked("隔离探针运行循环意外结束")
}

guard let connection = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      connection == "cn.jokerhub.inputmethod.LampyrisIMKTest.\(suffix.lowercased())_Connection",
      let server = IMKServer(name: connection, bundleIdentifier: Bundle.main.bundleIdentifier)
else { blocked("独立IMK连接初始化失败") }
print("READY server \(getpid())")
fflush(stdout)
withExtendedLifetime(server) { NSApplication.shared.run() }
