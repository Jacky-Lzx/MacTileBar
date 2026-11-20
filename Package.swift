// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacTileBar",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.4.5")
    ],
    targets: [
        .executableTarget(
            name: "MacTileBar",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .testTarget(name: "MacTileBarTests", dependencies: ["MacTileBar"])
    ]
)
