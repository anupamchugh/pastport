// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pastport",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "PastportKit", targets: ["PastportKit"]),
        .library(name: "PastportUI", targets: ["PastportUI"]),
        .library(name: "PastportMac", targets: ["PastportMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rryam/FoundationModelsKit.git",
                 revision: "65834b11d6da41e4a2f51003eba930b211d6f031"),
        .package(url: "https://github.com/rudrankriyam/Foundation-Models-Framework-Lab.git",
                 revision: "9e3dd5ae24ba6821626f24bfbbb187f4b88d7efe"),
    ],
    targets: [
        // Cross-platform core: domain, detectors, sources as protocols, on-device AI.
        .target(name: "PastportKit", dependencies: [
            .product(name: "FoundationModelsKit", package: "FoundationModelsKit"),
            .product(name: "FoundationModelsTools", package: "FoundationModelsKit"),
            .product(name: "FoundationLabCore", package: "Foundation-Models-Framework-Lab"),
        ]),
        // Shared SwiftUI views for the Mac and iOS apps. No AppKit, UIKit or I/O.
        .target(name: "PastportUI", dependencies: [
            "PastportKit",
            .product(name: "FoundationLabCore", package: "Foundation-Models-Framework-Lab"),
        ]),
        // Mac-only adapters: Safari's database via /usr/bin/sqlite3, osascript, local Ollama.
        .target(name: "PastportMac", dependencies: ["PastportKit"]),
        // Fictional fixture and scorer for the Ask eval. Linked by the CLI only, never by an app.
        .target(name: "PastportEval", dependencies: ["PastportKit"]),
        .executableTarget(
            name: "pastport",
            dependencies: ["PastportKit", "PastportMac", "PastportEval"]
        ),
        .executableTarget(
            name: "PastportBar",
            dependencies: ["PastportKit", "PastportUI", "PastportMac"]
        ),
        .testTarget(
            name: "PastportKitTests",
            dependencies: ["PastportKit"]
        ),
        .testTarget(name: "PastportEvalTests", dependencies: ["PastportEval", "PastportKit"]),
        .testTarget(name: "PastportMacTests", dependencies: ["PastportMac"]),
    ],
    swiftLanguageModes: [.v5]
)
