// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NowPlayingController",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "NowPlayingController",
            path: "Sources/NowPlayingController"
        )
    ]
)
