// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "Micodex",
    defaultLocalization: "en",
    platforms: [.macOS(.v13), .watchOS(.v9)],
    products: [.library(name: "MicodexCore", targets: ["MicodexCore"])],
    targets: [
        .target(name: "MicodexCore", resources: [.process("Resources")]),
        .testTarget(name: "MicodexCoreTests", dependencies: ["MicodexCore"])
    ]
)
