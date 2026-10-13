// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetroCal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "RetroCal", path: "Sources/RetroCal"),
        .testTarget(name: "RetroCalTests", dependencies: ["RetroCal"], path: "Tests/RetroCalTests"),
    ]
)
