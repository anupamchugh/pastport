// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pastport",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PastportKit"),
        .executableTarget(
            name: "pastport",
            dependencies: ["PastportKit"]
        ),
        .executableTarget(
            name: "PastportBar",
            dependencies: ["PastportKit"]
        ),
        .testTarget(
            name: "PastportKitTests",
            dependencies: ["PastportKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
