import AppKit
import ApplicationServices
import Carbon
import CryptoKit
import SystemConfiguration

struct GuardFailure: Error, CustomStringConvertible {
    let description: String
    init(_ value: String) { description = value }
}

struct PressTarget: Codable, Equatable {
    let windowIndex: Int
    let childPath: [Int]
    let windowTitle: String
    let windowFrame: String
    let label: String
}

struct ProcessBinding: Codable {
    let pid: Int32
    let executable: String
    let sha256: String
    let launchedAt: Double
}

struct GuardedPressPlan: Codable {
    let operatorUID: UInt32
    let testUID: UInt32
    let home: String
    let sourceID: String
    let runDirectory: String
    let fixture: String
    let fixtureTitle: String
    let client: ProcessBinding
    let host: ProcessBinding
    let target: PressTarget
}

protocol PressBackend {
    associatedtype Element
    func context() throws -> [String: String]
    func resolve(_ target: PressTarget) throws -> Element
    func identity(_ element: Element) throws -> PressTarget
    func press(_ element: Element) throws
}

/// Checks and action share this process; never refocuses, searches by fuzzy label or retries.
func guardedPress<B: PressBackend>(_ backend: B, target: PressTarget) throws {
    let before = try backend.context()
    let element = try backend.resolve(target)
    guard try backend.identity(element) == target else { throw GuardFailure("目标身份变化") }
    guard try backend.context() == before else { throw GuardFailure("动作前上下文变化") }
    guard try backend.identity(element) == target else { throw GuardFailure("动作前目标变化") }
    try backend.press(element)
}

final class NativePressBackend: PressBackend {
    let plan: GuardedPressPlan
    init(_ plan: GuardedPressPlan) { self.plan = plan }

    private func attribute(_ element: AXUIElement, _ key: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success,
              let value else { throw GuardFailure("AX属性不可读：" + key) }
        return value
    }
    private func text(_ element: AXUIElement, _ key: String) throws -> String {
        guard let result = try attribute(element, key) as? String else { throw GuardFailure("AX文本类型不符") }
        return result
    }
    private func element(_ parent: AXUIElement, _ key: String) throws -> AXUIElement {
        let value = try attribute(parent, key)
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw GuardFailure("AX对象类型不符") }
        return value as! AXUIElement
    }
    private func children(_ parent: AXUIElement, _ key: String) throws -> [AXUIElement] {
        guard let result = try attribute(parent, key) as? [AXUIElement], result.count <= 256 else {
            throw GuardFailure("AX子对象数量或类型不符")
        }
        return result
    }
    private func frame(_ window: AXUIElement) throws -> String {
        let position = try attribute(window, kAXPositionAttribute)
        let size = try attribute(window, kAXSizeAttribute)
        guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw GuardFailure("AX窗口几何类型不符")
        }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else {
            throw GuardFailure("AX窗口几何不可读")
        }
        return NSStringFromRect(NSRect(origin: point, size: extent))
    }
    private func validateProcess(_ binding: ProcessBinding) throws -> NSRunningApplication {
        guard binding.pid > 0, binding.sha256.count == 64,
              let app = NSRunningApplication(processIdentifier: binding.pid), !app.isTerminated,
              let executable = app.executableURL, let launched = app.launchDate,
              executable.path == binding.executable,
              executable.resolvingSymlinksInPath().path == executable.path,
              launched.timeIntervalSince1970 == binding.launchedAt else {
            throw GuardFailure("进程PID/启动时间/路径不符")
        }
        let actual = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        guard actual == binding.sha256 else { throw GuardFailure("进程执行文件摘要不符") }
        return app
    }
    private func privateFile(_ path: URL, directory: Bool) throws {
        let info = try FileManager.default.attributesOfItem(atPath: path.path)
        guard path.standardizedFileURL.path == path.path,
              path.resolvingSymlinksInPath().path == path.path,
              info[.type] as? FileAttributeType == (directory ? .typeDirectory : .typeRegular),
              (info[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let permissions = info[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o077 == 0,
              directory || (info[.referenceCount] as? NSNumber)?.intValue == 1 else {
            throw GuardFailure("自有资源路径/归属/权限/链接不符")
        }
    }
    func context() throws -> [String: String] {
        guard getuid() == geteuid(), getuid() == plan.testUID, plan.testUID != 0,
              plan.testUID != plan.operatorUID, plan.operatorUID != 0,
              NSHomeDirectory() == plan.home else { throw GuardFailure("独立账号不符") }
        var consoleUID: uid_t = 0
        var consoleGID: gid_t = 0
        guard SCDynamicStoreCopyConsoleUser(nil, &consoleUID, &consoleGID) != nil,
              consoleUID == plan.testUID else { throw GuardFailure("GUI登录账号不符") }
        guard AXIsProcessTrusted() else { throw GuardFailure("AX权限未就绪") }
        let root = URL(fileURLWithPath: plan.runDirectory)
        let fixture = URL(fileURLWithPath: plan.fixture)
        guard root.lastPathComponent.hasPrefix("lampyris-formal-"),
              UUID(uuidString: String(root.lastPathComponent.dropFirst("lampyris-formal-".count))) != nil,
              fixture.deletingLastPathComponent().path == root.path,
              fixture.lastPathComponent == plan.fixtureTitle,
              plan.client.pid != plan.host.pid else { throw GuardFailure("测试资源绑定不符") }
        try privateFile(root, directory: true)
        try privateFile(fixture, directory: false)
        let clientApp = try validateProcess(plan.client)
        guard clientApp.bundleIdentifier == "com.apple.TextEdit" else {
            throw GuardFailure("当前仅支持拥有式TextEdit客户端")
        }
        let host = try validateProcess(plan.host)
        guard host.bundleIdentifier == "cn.jokerhub.inputmethod.Lampyris",
              plan.sourceID == "cn.jokerhub.inputmethod.Lampyris.default",
              host.bundleURL?.lastPathComponent == "Lampyris.app" else {
            throw GuardFailure("非正式宿主/输入源身份")
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == plan.client.pid else {
            throw GuardFailure("客户端前台变化")
        }
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let sourcePointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              Unmanaged<CFString>.fromOpaque(sourcePointer).takeUnretainedValue() as String == plan.sourceID else {
            throw GuardFailure("输入源变化")
        }
        let client = AXUIElementCreateApplication(plan.client.pid)
        let window = try element(client, kAXFocusedWindowAttribute)
        guard try text(window, kAXTitleAttribute) == plan.fixtureTitle,
              let document = URL(string: try text(window, kAXDocumentAttribute)),
              document.isFileURL, document.standardizedFileURL.path == fixture.path else {
            throw GuardFailure("聚焦文档身份不符")
        }
        let focus = try element(client, kAXFocusedUIElementAttribute)
        let focusWindow = try element(focus, kAXWindowAttribute)
        guard CFEqual(focusWindow, window), try text(focus, kAXRoleAttribute) == kAXTextAreaRole,
              (try attribute(focus, kAXFocusedAttribute) as? Bool) == true else {
            throw GuardFailure("聚焦文本域不符")
        }
        return ["source": plan.sourceID, "client": String(plan.client.pid), "host": String(plan.host.pid),
                "document": document.absoluteString, "window": try frame(window),
                "focus": String(CFHash(focus)), "fixture": plan.fixture]
    }
    func resolve(_ target: PressTarget) throws -> AXUIElement {
        guard (0..<128).contains(target.windowIndex), target.childPath.count <= 32,
              !target.label.isEmpty, target.label.count <= 512 else { throw GuardFailure("目标路径超界") }
        let app = AXUIElementCreateApplication(plan.host.pid)
        let windows = try children(app, kAXWindowsAttribute)
        guard target.windowIndex < windows.count else { throw GuardFailure("目标窗口不存在") }
        var result = windows[target.windowIndex]
        for index in target.childPath {
            let values = try children(result, kAXChildrenAttribute)
            guard values.indices.contains(index) else { throw GuardFailure("目标子路径不存在") }
            result = values[index]
        }
        return result
    }
    func identity(_ target: AXUIElement) throws -> PressTarget {
        var owner: pid_t = 0
        guard AXUIElementGetPid(target, &owner) == .success, owner == plan.host.pid,
              try text(target, kAXRoleAttribute) == kAXButtonRole,
              (try attribute(target, kAXEnabledAttribute) as? Bool) == true else {
            throw GuardFailure("非目标宿主可用按钮")
        }
        let window = try element(target, kAXWindowAttribute)
        let expectedWindow = try children(AXUIElementCreateApplication(plan.host.pid), kAXWindowsAttribute)
        guard expectedWindow.indices.contains(plan.target.windowIndex),
              CFEqual(window, expectedWindow[plan.target.windowIndex]) else { throw GuardFailure("目标窗口变化") }
        let current = try resolve(plan.target)
        guard CFEqual(current, target) else { throw GuardFailure("目标对象已替换") }
        let label: String
        if let description = try? text(target, kAXDescriptionAttribute), !description.isEmpty {
            label = description
        } else { label = try text(target, kAXTitleAttribute) }
        return PressTarget(windowIndex: plan.target.windowIndex, childPath: plan.target.childPath,
                           windowTitle: try text(window, kAXTitleAttribute), windowFrame: try frame(window), label: label)
    }
    func press(_ element: AXUIElement) throws {
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw GuardFailure("AXPress失败；未重试")
        }
    }
}
