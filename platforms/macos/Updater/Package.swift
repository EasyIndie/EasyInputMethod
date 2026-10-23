// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LampyrisWebsiteUpdater",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LampyrisUpdateCheck", targets: ["WebsiteUpdateCheck"])],
    targets: [
        .target(name: "OrzAppUpdaterCore", path: "Vendor/OrzAppUpdaterCore"),
        // ime-config 的头文件/静态库由 Makefile 与 build.py 以命令行参数传入，
        // 避免在 Package.swift 里写绝对路径或 unsafeFlags（CI 的 Xcode 驱动对此敏感）。
        .executableTarget(name: "WebsiteUpdateCheck", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(name: "OrzAppUpdaterCoreTests", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(name: "WebsiteUpdateCheckTests", dependencies: ["WebsiteUpdateCheck"]),
    ]
)
