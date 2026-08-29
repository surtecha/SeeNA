// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "SEENACore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "SEENACore", targets: ["SEENACore"])
    ],
    targets: [
        .target(
            name: "SEENACore",
            path: "SeeNA",
            exclude: [
                "App",
                "Assets.xcassets",
                "Audio",
                "Debug",
                "ContentView.swift",
                "Engines/GaborRenderer.swift",
                "Engines/LandoltCRenderer.swift",
                "Features",
                "Networking",
                "Persistence",
                "Resources",
                "Secrets.plist",
                "SeeNAApp.swift",
                "Sensors"
            ],
            sources: [
                "Models/DomainModels.swift",
                "Engines/BlockMeasurementQuality.swift",
                "Engines/DistanceGuidanceEngine.swift",
                "Engines/FaceAlignmentEngine.swift",
                "Engines/MeasurementEngines.swift",
                "Engines/GaborContrastEngine.swift",
                "Engines/MotionStationarityEvaluator.swift",
                "Engines/ResultIntegrityValidator.swift",
                "Engines/SequentialGaborSession.swift",
                "Engines/SequentialOptotypeSession.swift",
                "Engines/ThresholdSearchEngine.swift"
            ]
        ),
        .testTarget(
            name: "SEENACoreTests",
            dependencies: ["SEENACore"],
            path: "SeeNATests"
        )
    ]
)
