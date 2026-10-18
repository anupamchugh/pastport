// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pastport",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/rryam/FoundationModelsKit.git",
                 revision: "65834b11d6da41e4a2f51003eba930b211d6f031"),
        .package(url: "https://github.com/rudrankriyam/Foundation-Models-Framework-Lab.git",
                 revision: "9e3dd5ae24ba6821626f24bfbbb187f4b88d7efe"),
    ],
    targets: [
        .target(name: "PastportKit", dependencies: [
            .product(name: "FoundationModelsKit", package: "FoundationModelsKit"),
            .product(name: "FoundationModelsTools", package: "FoundationModelsKit"),
            .product(name: "FoundationLabCore", package: "Foundation-Models-Framework-Lab"),
        ]),
        .executableTarget(
            name: "pastport",
            dependencies: ["PastportKit"]
        ),
        .executableTarget(
            name: "PastportBar",
            dependencies: ["PastportKit"]
        ),
        .testTarget(name: "PastportBarTests", dependencies: ["PastportBar"]),
        .testTarget(
            name: "PastportKitTests",
            dependencies: ["PastportKit"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
