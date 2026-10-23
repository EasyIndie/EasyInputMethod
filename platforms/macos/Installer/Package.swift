// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LampyrisInstaller",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "LampyrisInstaller",
            path: "Sources/LampyrisInstaller",
            linkerSettings: [.linkedFramework("Security")]
        )
    ]
)
