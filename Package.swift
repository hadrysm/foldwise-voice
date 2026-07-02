// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FoldWiseVoice",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
    ],
    targets: [
        .target(
            name: "FoldWiseVoiceKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        .executableTarget(
            name: "FoldWiseVoice",
            dependencies: ["FoldWiseVoiceKit"]
        ),
        .testTarget(
            name: "FoldWiseVoiceKitTests",
            dependencies: ["FoldWiseVoiceKit"]
        ),
    ]
)
