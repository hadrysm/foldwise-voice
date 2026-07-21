// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FoldWiseVoice",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        // WhisperKit — the second ASR engine (ADR-0005). The repo was renamed from
        // argmaxinc/WhisperKit to argmaxinc/argmax-oss-swift at v1.0.0 (2026-05-01),
        // folding WhisperKit into a multi-kit SDK; product `WhisperKit`, macOS 14+.
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "FoldWiseVoiceKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .executableTarget(
            name: "FoldWiseVoice",
            dependencies: ["FoldWiseVoiceKit"]
        ),
        // PROTOTYPE ONLY (Wayfinder #225): three throwaway Models-view structures.
        // Run with `swift run ModelsViewPrototype`; delete after the design decision.
        .executableTarget(name: "ModelsViewPrototype"),
        .testTarget(
            name: "FoldWiseVoiceKitTests",
            dependencies: ["FoldWiseVoiceKit"]
        ),
    ]
)
