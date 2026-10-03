// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebcamView",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "WebcamView",
            path: "Sources/WebcamView"
        )
    ]
)
