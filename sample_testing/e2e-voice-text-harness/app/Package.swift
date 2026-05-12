// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VoiceTextDemo",
    platforms: [
        .iOS(.v17)
    ],
    targets: [
        .executableTarget(
            name: "VoiceTextDemo",
            dependencies: [],
            path: "VoiceTextDemo"
        )
    ]
)
