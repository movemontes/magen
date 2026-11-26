// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Magen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MagenCore"),
        .executableTarget(name: "magend", dependencies: ["MagenCore"]),
        .executableTarget(name: "magen", dependencies: ["MagenCore"]),
        .executableTarget(name: "magen-selftest", dependencies: ["MagenCore"]),
    ]
)
