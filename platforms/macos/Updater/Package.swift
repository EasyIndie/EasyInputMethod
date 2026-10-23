// swift-tools-version: 5.10
import Foundation
import PackageDescription

// 仓库根目录：本文件在 platforms/macos/Updater 下。
let root = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let ffiInclude = root.appendingPathComponent("crates/ime-ffi/include").path
let ffiLibrary = root.appendingPathComponent("target/release").path

let package = Package(
    name: "LampyrisWebsiteUpdater",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LampyrisUpdateCheck", targets: ["WebsiteUpdateCheck"])],
    targets: [
        .target(name: "OrzAppUpdaterCore", path: "Vendor/OrzAppUpdaterCore"),
        // 更新程序只在读取「更新来源」时使用 ime-config（配置唯一来源）；
        // core 仍零网络、零 IO，不链接输入法宿主。
        .executableTarget(
            name: "WebsiteUpdateCheck",
            dependencies: ["OrzAppUpdaterCore"],
            swiftSettings: [.unsafeFlags(["-I", ffiInclude])],
            linkerSettings: [.unsafeFlags(["-L", ffiLibrary, "-lime_ffi"])]),
        .testTarget(name: "OrzAppUpdaterCoreTests", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(
            name: "WebsiteUpdateCheckTests",
            dependencies: ["WebsiteUpdateCheck"],
            swiftSettings: [.unsafeFlags(["-I", ffiInclude])],
            linkerSettings: [.unsafeFlags(["-L", ffiLibrary, "-lime_ffi"])]),
    ]
)
