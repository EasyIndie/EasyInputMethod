// Headless probe for the shared install core (ADR-295): replacement, backup, rollback and
// self-update semantics that the DMG installer, the updater and the CLI all rely on.
import CryptoKit
import Foundation
import LampyrisInstallCore

func require(_ value: Bool, _ message: String) {
    guard value else { fputs("FAIL \(message)\n", stderr); exit(1) }
}

let root = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("lampyris-install-core-\(UUID().uuidString)")
let home = root.appendingPathComponent("home")
let domain = home.appendingPathComponent("Library/Input Methods")
let support = home.appendingPathComponent("Library/Application Support/Lampyris")
let applications = home.appendingPathComponent("Applications")
for directory in [domain, support, applications] {
    try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
defer { try? FileManager.default.removeItem(at: root) }

func makeBundle(at parent: URL, named name: String, identity: String, executable: String,
                mark: String) -> URL {
    let bundle = parent.appendingPathComponent("\(UUID().uuidString)-\(name)")
    let contents = bundle.appendingPathComponent("Contents")
    try! FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"),
                                             withIntermediateDirectories: true)
    let info: [String: Any] = ["CFBundleIdentifier": identity, "CFBundleExecutable": executable,
                               "CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]
    try! PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        .write(to: contents.appendingPathComponent("Info.plist"))
    try! mark.write(to: contents.appendingPathComponent("MacOS/\(executable)"),
                    atomically: true, encoding: .utf8)
    return bundle
}

func mark(_ url: URL, _ executable: String) -> String {
    (try? String(contentsOf: url.appendingPathComponent("Contents/MacOS/\(executable)"),
                   encoding: .utf8)) ?? "missing"
}

/// Validation stub: only accepts the expected marker so post-install checks can fail on demand.
func environment(expect: String, executable: String) -> InstallEnvironment {
    InstallEnvironment(validateCandidate: { candidate in
        let value = mark(candidate, executable)
        guard value == expect else { throw InstallError.candidateInvalid("unexpected \(value)") }
    }, stopHost: { _ in })
}

let candidates = root.appendingPathComponent("candidates")
try! FileManager.default.createDirectory(at: candidates, withIntermediateDirectories: true)
let hostDestination = domain.appendingPathComponent("Lampyris.app")
let backupRoot = support.appendingPathComponent("updates/dmg-backup-probe")
let hostEnvironment = environment(expect: "host-newer", executable: "Lampyris")

// 1) fresh install into an existing domain
let first = makeBundle(at: candidates, named: "Lampyris.app",
                       identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                       mark: "host-newer")
let firstBackup = try! UpdateInstaller.replaceBundle(
    candidate: first, destination: hostDestination, backupRoot: backupRoot,
    environment: hostEnvironment)
require(firstBackup == nil, "fresh install must not report a backup")
require(mark(hostDestination, "Lampyris") == "host-newer", "fresh install must place the bundle")

// 2) upgrade keeps the previous bundle as a backup
let second = makeBundle(at: candidates, named: "Lampyris.app",
                        identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                        mark: "host-newest")
let secondBackup = try! UpdateInstaller.replaceBundle(
    candidate: second, destination: hostDestination, backupRoot: backupRoot,
    environment: environment(expect: "host-newest", executable: "Lampyris"))
require(mark(hostDestination, "Lampyris") == "host-newest", "upgrade must install the new bundle")
require(mark(URL(fileURLWithPath: secondBackup ?? ""), "Lampyris") == "host-newer",
        "upgrade must back up the previous bundle")

// 3) post-install validation failure restores the previous bundle
let broken = makeBundle(at: candidates, named: "Lampyris.app",
                        identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                        mark: "host-broken")
var calls = 0
let failingEnvironment = InstallEnvironment(validateCandidate: { candidate in
    calls += 1
    if calls >= 2 { throw InstallError.candidateInvalid("post-install") }
    require(mark(candidate, "Lampyris") == "host-broken", "pre-install candidate content")
}, stopHost: { _ in })
do {
    _ = try UpdateInstaller.replaceBundle(
        candidate: broken, destination: hostDestination, backupRoot: backupRoot,
        environment: failingEnvironment)
    require(false, "post-install validation failure must throw")
} catch {
    require(mark(hostDestination, "Lampyris") == "host-newest", "failure must restore the previous bundle")
}

// 4) symlinked destination and missing domain are rejected without touching anything
let linkedRoot = root.appendingPathComponent("linked")
try! FileManager.default.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
let realBundle = makeBundle(at: candidates, named: "Lampyris.app",
                            identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                            mark: "host-newest")
let staged = linkedRoot.appendingPathComponent("keep.app")
try! FileManager.default.copyItem(at: realBundle, to: staged)
try! FileManager.default.createSymbolicLink(at: linkedRoot.appendingPathComponent("Lampyris.app"),
                                            withDestinationURL: staged)
do {
    _ = try UpdateInstaller.replaceBundle(
        candidate: makeBundle(at: candidates, named: "Lampyris.app",
                              identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                              mark: "host-newest"),
        destination: linkedRoot.appendingPathComponent("Lampyris.app"), backupRoot: backupRoot,
        environment: hostEnvironment)
    require(false, "symlinked destination must be rejected")
} catch let error as InstallError {
    if case .symlinkRejected = error {} else { require(false, "expected symlinkRejected, got \(error)") }
}
do {
    _ = try UpdateInstaller.replaceBundle(
        candidate: realBundle, destination: root.appendingPathComponent("missing/Lampyris.app"),
        backupRoot: backupRoot, environment: hostEnvironment)
    require(false, "missing domain must be rejected (ADR-289)")
} catch let error as InstallError {
    if case .domainMissing = error {} else { require(false, "expected domainMissing, got \(error)") }
}
require(mark(staged, "Lampyris") == "host-newest", "rejected installs must leave the existing bundle alone")

// 5) self-update installs the sibling updater bundle into ~/Applications and keeps a backup
let staging = root.appendingPathComponent("payload-staging")
try! FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
let selfUpdate = UpdateInstaller.SelfUpdate(
    directory: applications,
    environment: environment(expect: "updater-new", executable: "LampyrisUpdateCheck"))
require(try! UpdateInstaller.installSelfUpdate(selfUpdate, payloadStaging: staging) == nil,
        "payload without an updater bundle must not self-update")
let updaterCandidate = makeBundle(at: staging, named: "LampyrisUpdateCheck.app",
                                  identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                                  executable: "LampyrisUpdateCheck", mark: "updater-new")
try! FileManager.default.moveItem(
    at: updaterCandidate,
    to: staging.appendingPathComponent(InstallTarget.updater.bundleName))
let installedUpdater = try! UpdateInstaller.installSelfUpdate(selfUpdate, payloadStaging: staging)
require(installedUpdater?.installed == applications.appendingPathComponent("LampyrisUpdateCheck.app").path,
        "self-update must report the installed path")
require(installedUpdater?.previous == nil, "first self-update has nothing to back up")
require(mark(applications.appendingPathComponent("LampyrisUpdateCheck.app"), "LampyrisUpdateCheck")
        == "updater-new", "self-update must install the updater bundle")

// 6) self-update over an existing updater replaces it and reports failures instead of destroying it
let staging2 = root.appendingPathComponent("payload-staging-2")
try! FileManager.default.createDirectory(at: staging2, withIntermediateDirectories: true)
let newer = makeBundle(at: staging2, named: "LampyrisUpdateCheck.app",
                       identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                       executable: "LampyrisUpdateCheck", mark: "updater-newer")
try! FileManager.default.moveItem(
    at: newer, to: staging2.appendingPathComponent(InstallTarget.updater.bundleName))
_ = try! UpdateInstaller.installSelfUpdate(
    UpdateInstaller.SelfUpdate(directory: applications,
                               environment: environment(expect: "updater-newer",
                                                        executable: "LampyrisUpdateCheck")),
    payloadStaging: staging2)
require(mark(applications.appendingPathComponent("LampyrisUpdateCheck.app"), "LampyrisUpdateCheck")
        == "updater-newer", "self-update must replace an older updater")

// 7) 回执写入失败 = 整笔失败：输入法与自更新都回到升级前（报告142 的语义，不能悄悄放宽）
let payloadRoot = root.appendingPathComponent("payload")
let package = payloadRoot.appendingPathComponent("Lampyris-1.0-universal")
try! FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
let payloadHost = makeBundle(at: package, named: "Lampyris.app",
                             identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                             mark: "payload-host")
try! FileManager.default.moveItem(at: payloadHost, to: package.appendingPathComponent("Lampyris.app"))
let payloadUpdater = makeBundle(at: package, named: "LampyrisUpdateCheck.app",
                                identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                                executable: "LampyrisUpdateCheck", mark: "payload-updater")
try! FileManager.default.moveItem(at: payloadUpdater,
                                 to: package.appendingPathComponent("LampyrisUpdateCheck.app"))
let payload = root.appendingPathComponent("payload.zip")
let zipper = Process()
zipper.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
zipper.arguments = ["-c", "-k", "--keepParent", package.path, payload.path]
try! zipper.run()
zipper.waitUntilExit()
require(zipper.terminationStatus == 0, "payload zip must be created")

let signingKey = Curve25519.Signing.PrivateKey()
let payloadBytes = try! Data(contentsOf: payload)
let signature = try! signingKey.signature(for: payloadBytes).base64EncodedString()
let publicKey = signingKey.publicKey.rawRepresentation.base64EncodedString()

let receiptSupport = root.appendingPathComponent("support-with-file-receipts")
try! FileManager.default.createDirectory(at: receiptSupport, withIntermediateDirectories: true)
try! Data().write(to: receiptSupport.appendingPathComponent("receipts"))  // 目录位置被文件占用

let beforeUpdater = mark(applications.appendingPathComponent("LampyrisUpdateCheck.app"),
                         "LampyrisUpdateCheck")
let receiptDomain = root.appendingPathComponent("receipt-domain")
let installedHost = receiptDomain.appendingPathComponent("Lampyris.app")
try! FileManager.default.createDirectory(at: receiptDomain, withIntermediateDirectories: true)
try! FileManager.default.copyItem(at: realBundle, to: installedHost)
var receiptFailed = false
do {
    _ = try UpdateInstaller.install(
        payload: payload, signature: signature, publicKeyBase64: publicKey,
        domain: receiptDomain, support: receiptSupport,
        environment: environment(expect: "payload-host", executable: "Lampyris"),
        selfUpdate: UpdateInstaller.SelfUpdate(
            directory: applications,
            environment: environment(expect: "payload-updater", executable: "LampyrisUpdateCheck")))
} catch {
    receiptFailed = true
}
require(receiptFailed, "receipt failure must fail the whole install")
require(mark(installedHost, "Lampyris") == "host-newest",
        "receipt failure must restore the previous input method bundle")
require(mark(applications.appendingPathComponent("LampyrisUpdateCheck.app"), "LampyrisUpdateCheck")
        == beforeUpdater, "receipt failure must restore the previous updater bundle")

// 8) 卸载（ADR-296）：默认保留 config.toml 与个人词库，更新程序本体留到进程退出后删除
func fixtureUninstall(named name: String) -> (UninstallPaths, URL, URL, URL, URL, URL) {
    let home = root.appendingPathComponent(name)
    let domain = home.appendingPathComponent("Library/Input Methods")
    let applications = home.appendingPathComponent("Applications")
    let support = home.appendingPathComponent("Library/Application Support/Lampyris")
    for directory in [domain, applications, support] {
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let host = makeBundle(at: domain, named: "Lampyris.app",
                          identity: "cn.jokerhub.inputmethod.Lampyris", executable: "Lampyris",
                          mark: "host")
    try! FileManager.default.moveItem(at: host, to: domain.appendingPathComponent("Lampyris.app"))
    let updater = makeBundle(at: applications, named: "LampyrisUpdateCheck.app",
                             identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                             executable: "LampyrisUpdateCheck", mark: "updater")
    try! FileManager.default.moveItem(at: updater,
                                     to: applications.appendingPathComponent("LampyrisUpdateCheck.app"))
    let legacy = makeBundle(at: applications, named: "Lampyris Update.app",
                            identity: "cn.jokerhub.Lampyris.WebsiteUpdateCheck",
                            executable: "LampyrisUpdateCheck", mark: "legacy")
    try! FileManager.default.moveItem(at: legacy,
                                     to: applications.appendingPathComponent("Lampyris Update.app"))
    try! "mode = \"wubi\"\n".write(to: support.appendingPathComponent("config.toml"),
                                    atomically: true, encoding: .utf8)
    try! "dict\n".write(to: support.appendingPathComponent("user-dictionary.tsv"),
                         atomically: true, encoding: .utf8)
    try! FileManager.default.createDirectory(at: support.appendingPathComponent("updates/backup"),
                                             withIntermediateDirectories: true)
    return (UninstallPaths(home: home, domain: domain, applications: applications, support: support),
            domain.appendingPathComponent("Lampyris.app"),
            applications.appendingPathComponent("LampyrisUpdateCheck.app"),
            applications.appendingPathComponent("Lampyris Update.app"),
            support.appendingPathComponent("config.toml"),
            support.appendingPathComponent("user-dictionary.tsv"))
}

let (keepPaths, keepHost, keepUpdater, keepLegacy, keepConfig, keepDictionary) =
    fixtureUninstall(named: "uninstall-keep")
let keepPlan = try! UninstallerCore.plan(mode: .keepData, paths: keepPaths, selfBundle: keepUpdater)
require(keepPlan.pendingSelfRemoval == [keepUpdater.path], "running updater must be deferred, not deleted")
require(keepPlan.kept.contains(keepConfig.path) && keepPlan.kept.contains(keepDictionary.path),
        "keepData must keep config and dictionary")
require(keepPlan.targets.contains(keepHost.path) && keepPlan.targets.contains(keepLegacy.path),
        "host and legacy updater must be deleted")
require(keepPlan.targets.contains(keepPaths.support.appendingPathComponent("updates").path),
        "update backups must be removed")
let keepOutcome = try! UninstallerCore.run(
    mode: .keepData, paths: keepPaths, selfBundle: keepUpdater,
    stopApps: { _ in }, switchToABCAndDisable: { _ in })
require(!FileManager.default.fileExists(atPath: keepHost.path), "host bundle must be gone")
require(!FileManager.default.fileExists(atPath: keepLegacy.path), "legacy updater must be gone")
require(FileManager.default.fileExists(atPath: keepConfig.path), "config must survive keepData")
require(FileManager.default.fileExists(atPath: keepDictionary.path), "dictionary must survive keepData")
require(!FileManager.default.fileExists(atPath: keepPaths.support.appendingPathComponent("updates").path),
        "update backups must be gone")
require(FileManager.default.fileExists(atPath: keepUpdater.path),
        "running updater bundle is deleted only after exit")
require(keepOutcome.pendingSelfRemoval == [keepUpdater.path], "self-removal path must be reported")

let script = UninstallerCore.selfRemovalScript(pid: 4242, paths: [keepUpdater.path])
require(script.contains("kill -0 4242"), "script must wait for the caller pid")
require(script.contains("rm -rf -- '" + keepUpdater.path + "'"), "script must quote the pending path")

let (purgePaths, purgeHost, purgeUpdater, _, purgeConfig, _) =
    fixtureUninstall(named: "uninstall-purge")
_ = try! UninstallerCore.run(mode: .removeAll, paths: purgePaths, selfBundle: purgeUpdater,
                             stopApps: { _ in }, switchToABCAndDisable: { _ in })
require(!FileManager.default.fileExists(atPath: purgeHost.path), "removeAll must remove the host")
require(!FileManager.default.fileExists(atPath: purgeConfig.path), "removeAll must remove config")
require(!FileManager.default.fileExists(atPath: purgePaths.support.path),
        "removeAll must remove the data directory")

// 标识不符的输入法目录必须拒绝（避免误删别人的 app）
let (wrongPaths, wrongHost, _, _, _, _) = fixtureUninstall(named: "uninstall-wrong")
try! FileManager.default.removeItem(at: wrongHost)
let foreign = makeBundle(at: wrongPaths.domain, named: "Lampyris.app", identity: "com.example.other",
                         executable: "Lampyris", mark: "other")
try! FileManager.default.moveItem(at: foreign, to: wrongPaths.domain.appendingPathComponent("Lampyris.app"))
do {
    _ = try UninstallerCore.plan(mode: .keepData, paths: wrongPaths)
    require(false, "foreign bundle identity must be rejected")
} catch let error as UninstallError {
    if case .invalidApp = error {} else { require(false, "expected invalidApp, got \(error)") }
}

print("PASS install-core: replace/backup/rollback/self-update/receipt-rollback/uninstall semantics")
