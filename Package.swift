// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToneBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ToneBar",
            path: "Sources/ToneBar"
        )
    ]
)
