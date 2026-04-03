// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "NeuroSkySDK",
    platforms: [
        .iOS(.v14),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "NeuroSkySDK",
            targets: ["NeuroSkySDK"]
        ),
    ],
    targets: [
        .target(
            name: "NeuroSkySDK",
            path: "Sources/NeuroSkySDK"
        ),
        .testTarget(
            name: "NeuroSkySDKTests",
            dependencies: ["NeuroSkySDK"],
            path: "Tests/NeuroSkySDKTests"
        ),
    ]
)
