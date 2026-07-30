// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shark",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(
            name: "Shark",
            path: "Sources/Shark"
        )
    ]
)
