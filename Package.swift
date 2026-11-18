// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Float",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.7.3"),
    ],
    targets: [
        .target(name: "FloatCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")]),
        .executableTarget(name: "Float", dependencies: ["FloatCore"]),
        .testTarget(name: "FloatCoreTests", dependencies: ["FloatCore"]),
    ]
)
