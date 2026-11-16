// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FocusNest",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FocusNest", targets: ["FocusNest"])],
    targets: [
        .target(name: "FocusCore"),
        .executableTarget(name: "DeadlineChecks", dependencies: ["FocusCore"], path: "Tests/DeadlineChecks"),
        .executableTarget(name: "FocusNest", dependencies: ["FocusCore"]),
        .executableTarget(name: "FocusCoreChecks", dependencies: ["FocusCore"], path: "Tests/FocusCoreTests")
    ]
)
