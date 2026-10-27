// swift-tools-version: 5.9
import PackageDescription

// ADR-295：安装器不再自带一份「校验 → 备份 → 替换 → 回滚」，改用共享的 InstallCore。
let package = Package(
    name: "LampyrisInstaller",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../InstallCore")],
    targets: [
        .executableTarget(
            name: "LampyrisInstaller",
            dependencies: [.product(name: "LampyrisInstallCore", package: "InstallCore")],
            path: "Sources/LampyrisInstaller",
            linkerSettings: [.linkedFramework("Security")]
        )
    ]
)
