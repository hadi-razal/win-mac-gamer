// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LocalPlay",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "LocalPlay", targets: ["LocalPlay"]), .executable(name: "localplayctl", targets: ["localplayctl"])],
    targets: [
        .target(name: "LocalPlayCore"),
        .executableTarget(name: "LocalPlay", dependencies: ["LocalPlayCore"]),
        .executableTarget(name: "localplayctl", dependencies: ["LocalPlayCore"]),
        .testTarget(name: "LocalPlayCoreTests", dependencies: ["LocalPlayCore"])
    ],
    swiftLanguageModes: [.v5]
)
