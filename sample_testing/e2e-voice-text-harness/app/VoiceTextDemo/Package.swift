// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceTextDemo",
    platforms: [.iOS(.v17)],
    products: [
        .executable(name: "VoiceTextDemo", targets: ["VoiceTextDemo"])
    ],
    targets: [
        .executableTarget(
            name: "VoiceTextDemo",
            path: ".",
            sources: [
                "AudioManager.swift", 
                "ChatViewModel.swift", 
                "ContentView.swift", 
                "VoiceTextDemoApp.swift"
            ]
        ),
        .testTarget(
            name: "AudioBridgeTests",
            dependencies: ["VoiceTextDemo"],
            path: ".", 
            sources: ["AudioBridgeTests.swift"] 
        )
    ]
)