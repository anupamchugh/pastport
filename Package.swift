// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pastport",
    platforms: [.macOS("27.0"), .iOS("27.0")],
    products: [
        .library(name: "PastportKit", targets: ["PastportKit"]),
        .library(name: "PastportConnected", targets: ["PastportConnected"]),
        .library(name: "PastportUI", targets: ["PastportUI"]),
        .library(name: "PastportMac", targets: ["PastportMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rryam/FoundationModelsKit.git",
                 revision: "65834b11d6da41e4a2f51003eba930b211d6f031"),
    ],
    targets: [
        // Cross-platform core: domain, detectors, sources as protocols, on-device AI. It links no
        // package except FoundationModelsKit, so another app can depend on it alone.
        .target(name: "PastportKit", dependencies: [
            .product(name: "FoundationModelsKit", package: "FoundationModelsKit"),
        ], swiftSettings: [.swiftLanguageMode(.v6)]),
        // Opt-in Connected tools (weather, web, contacts, calendar...). Registered on a TimelineModel by the apps.
        .target(name: "PastportConnected", dependencies: [
            "PastportKit",
            .product(name: "FoundationModelsKit", package: "FoundationModelsKit"),
            .product(name: "FoundationModelsTools", package: "FoundationModelsKit"),
        ], swiftSettings: [.swiftLanguageMode(.v6)]),
        // Shared SwiftUI views for the Mac and iOS apps. No AppKit, UIKit or I/O.
        .target(name: "PastportUI", dependencies: [
            "PastportKit",
            "PastportConnected",
        ], swiftSettings: [.swiftLanguageMode(.v6)]),
        // Mac-only adapters: Safari's database via /usr/bin/sqlite3, osascript, local Ollama.
        .target(name: "PastportMac", dependencies: ["PastportKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        // Fictional fixture and scorer for the Ask eval. Linked by the CLI only, never by an app.
        .target(name: "PastportEval", dependencies: ["PastportKit"], swiftSettings: [.swiftLanguageMode(.v6)]),
        .executableTarget(
            name: "pastport",
            dependencies: ["PastportKit", "PastportMac", "PastportEval"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "PastportBar",
            dependencies: ["PastportKit", "PastportConnected", "PastportUI", "PastportMac"]
        ),
        .testTarget(
            name: "PastportKitTests",
            dependencies: ["PastportKit"]
        ),
        .testTarget(name: "PastportConnectedTests", dependencies: ["PastportConnected", "PastportKit"]),
        .testTarget(name: "PastportEvalTests", dependencies: ["PastportEval", "PastportKit"]),
        .testTarget(name: "PastportMacTests", dependencies: ["PastportMac", "PastportKit"]),
    ],
    swiftLanguageModes: [.v5]
)
