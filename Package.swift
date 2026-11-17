// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Float",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FloatCore"),
        .executableTarget(name: "Float", dependencies: ["FloatCore"]),
        .testTarget(name: "FloatCoreTests", dependencies: ["FloatCore"]),
    ]
)
