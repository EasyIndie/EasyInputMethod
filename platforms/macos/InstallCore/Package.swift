// swift-tools-version: 5.9
import PackageDescription

// ADR-295：DMG 安装器与独立更新程序共用同一份「校验 → 备份 → 替换 → 回滚」实现。
// 本包只依赖 Foundation/CryptoKit，不链接 ime-ffi，也不联网。
let package = Package(
    name: "LampyrisInstallCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "LampyrisInstallCore", targets: ["LampyrisInstallCore"])],
    targets: [
        .target(name: "LampyrisInstallCore"),
        .testTarget(name: "LampyrisInstallCoreTests", dependencies: ["LampyrisInstallCore"]),
    ]
)
