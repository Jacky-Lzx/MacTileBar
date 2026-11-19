// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTileBar",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "MacTileBar"),
        .testTarget(name: "MacTileBarTests", dependencies: ["MacTileBar"])
    ]
)
