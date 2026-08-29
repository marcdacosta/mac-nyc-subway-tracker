// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacNYCSubwayTracker",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacNYCSubwayTracker",
            targets: ["MacNYCSubwayTrackerMenuBar"]
        )
    ],
    targets: [
        .target(name: "MacNYCSubwayTrackerCore"),
        .executableTarget(
            name: "MacNYCSubwayTrackerMenuBar",
            dependencies: ["MacNYCSubwayTrackerCore"]
        ),
        .testTarget(
            name: "MacNYCSubwayTrackerCoreTests",
            dependencies: ["MacNYCSubwayTrackerCore"]
        )
    ]
)
