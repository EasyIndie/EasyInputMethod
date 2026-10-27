// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LampyrisWebsiteUpdater",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LampyrisUpdateCheck", targets: ["WebsiteUpdateCheck"])],
    // ADR-295：安装/替换/回滚与负载验签来自共享的 InstallCore（DMG 安装器也是它的调用方）。
    dependencies: [.package(path: "../InstallCore")],
    targets: [
        .target(name: "OrzAppUpdaterCore", path: "Vendor/OrzAppUpdaterCore"),
        // ime-config 的头文件/静态库由 Makefile 与 build.py 以命令行参数传入，
        // 避免在 Package.swift 里写绝对路径或 unsafeFlags（CI 的 Xcode 驱动对此敏感）。
        .executableTarget(
            name: "WebsiteUpdateCheck",
            dependencies: ["OrzAppUpdaterCore",
                           .product(name: "LampyrisInstallCore", package: "InstallCore")]),
        .testTarget(name: "OrzAppUpdaterCoreTests", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(
            name: "WebsiteUpdateCheckTests",
            dependencies: ["WebsiteUpdateCheck",
                           .product(name: "LampyrisInstallCore", package: "InstallCore")]),
    ]
)
