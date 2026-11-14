// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BirdCore",
    platforms: [
        .macOS(.v14),   // so `swift test` runs on the Mac
        .iOS(.v17)      // the app target consumes the same package
    ],
    products: [
        .library(name: "BirdCore", targets: ["BirdCore"])
    ],
    targets: [
        .target(name: "BirdCore"),
        .testTarget(
            name: "BirdCoreTests",
            dependencies: ["BirdCore"],
            path: "Tests/BirdCoreTests"
        )
    ]
)
