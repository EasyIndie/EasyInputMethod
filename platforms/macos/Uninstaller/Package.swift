// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LampyrisUninstaller",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../InstallCore")],
    targets: [
        .executableTarget(
            name: "LampyrisUninstaller",
            dependencies: [.product(name: "LampyrisInstallCore", package: "InstallCore")],
            path: "Sources/LampyrisUninstaller"
        )
    ]
)
