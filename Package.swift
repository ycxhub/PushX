// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PushupCoachEngineTests",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "EngineCore",
            path: "PushupCoach",
            sources: [
                "PoseProvider.swift",
                "PushupPoseConstants.swift",
                "RepCountingEngine.swift",
                "FormScoringEngine.swift",
                "PoseTrackingGate.swift",
                "LandmarkSmoother.swift",
            ]
        ),
        .testTarget(
            name: "EngineTests",
            dependencies: ["EngineCore"],
            path: "Tests/EngineTests"
        ),
    ]
)
