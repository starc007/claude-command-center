// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeCommandCenter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ClaudeCommandCenter", targets: ["ClaudeCommandCenter"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeCommandCenter",
            path: "Sources/ClaudeCommandCenter"
        )
    ]
)
