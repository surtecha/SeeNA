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
                "ContentView.swift",
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
                "Engines/MeasurementEngines.swift",
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
