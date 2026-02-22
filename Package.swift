// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pulseinator",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Pulseinator",
            path: "Sources/Pulseinator"
        )
    ]
)
