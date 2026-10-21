// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "LampyrisWebsiteUpdater",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LampyrisUpdateCheck", targets: ["WebsiteUpdateCheck"])],
    targets: [
        .target(name: "OrzAppUpdaterCore", path: "Vendor/OrzAppUpdaterCore"),
        .executableTarget(name: "WebsiteUpdateCheck", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(name: "OrzAppUpdaterCoreTests", dependencies: ["OrzAppUpdaterCore"]),
        .testTarget(name: "WebsiteUpdateCheckTests", dependencies: ["WebsiteUpdateCheck"]),
    ]
)
