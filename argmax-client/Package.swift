// swift-tools-version: 6.0
//
// BirdLogClient: on-device voice input for BirdLog via Argmax WhisperKit.
//
// Engine: the Argmax open-source SDK (https://github.com/argmaxinc/argmax-oss-swift)
// — same vendor as the Pro SDK used by the hackathon sample
// (argmax-pro-sdk/native), but it builds without an Argmax registry token.
// Once you have the Pro credentials, see ../pro-variant/ to switch
// (custom vocabulary + LiveTranscriber are the main upgrades).
//
import PackageDescription

// Swift 5 language mode: the audio tap callbacks mutate engine state, and
// strict concurrency checking isn't worth the churn for a hackathon client.
let package = Package(
    name: "BirdLogClient",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "birdlog", targets: ["BirdLogClient"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.9.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "BirdLogClient",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
