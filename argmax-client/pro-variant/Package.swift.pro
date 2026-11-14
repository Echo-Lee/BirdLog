// swift-tools-version: 6.0
//
// Pro variant Package.swift — replace ../Package.swift with this after the
// one-time Argmax registry login (see README.md in this folder).
//
import PackageDescription

let package = Package(
    name: "BirdLogClient",
    platforms: [
        .macOS(.v15),   // Pro SDK minimum
    ],
    products: [
        .executable(name: "birdlog", targets: ["BirdLogClient"]),
    ],
    dependencies: [
        // Pro SDK from the Argmax registry (not GitHub). Install guide pins
        // 3.0.6; some docs use 2.0.9 — check the changelog if signatures drift.
        .package(id: "argmaxinc.argmax-sdk-swift", from: "3.0.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "BirdLogClient",
            dependencies: [
                .product(name: "Argmax", package: "argmaxinc.argmax-sdk-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)