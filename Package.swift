// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ToneBar",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/tahby/LayaKit", from: "0.1.0")
    ],
    targets: [
        .executableTarget(
            name: "ToneBar",
            dependencies: [.product(name: "LayaKit", package: "LayaKit")],
            path: "Sources/ToneBar"
        ),
        .executableTarget(
            name: "tonebar-eval",
            dependencies: [.product(name: "LayaKit", package: "LayaKit")],
            path: "Sources/tonebar-eval"
        )
    ]
)
