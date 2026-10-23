// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ForeCal",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ForeCal", path: "Sources/ForeCal"),
        .testTarget(name: "ForeCalTests", dependencies: ["ForeCal"], path: "Tests/ForeCalTests"),
    ]
)
