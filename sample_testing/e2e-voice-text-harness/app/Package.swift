// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceTextDemo",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "VoiceTextDemo", targets: ["VoiceTextDemo"])
    ],
    targets: [
        .target(
            name: "VoiceTextDemo",
            path: "Sources/VoiceTextDemo",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AudioBridgeTests",
            dependencies: ["VoiceTextDemo"],
            path: "Tests/AudioBridgeTests"
        )
    ]
)
