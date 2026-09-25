// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WatchWhisper",
    platforms: [.macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "WhisperCore", targets: ["WhisperCore"])],
    targets: [
        .target(name: "WhisperCore"),
        .testTarget(name: "WhisperCoreTests", dependencies: ["WhisperCore"])
    ]
)
