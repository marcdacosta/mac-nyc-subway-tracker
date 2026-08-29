// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Nostrand",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Nostrand", targets: ["NostrandMenuBar"])
    ],
    targets: [
        .target(name: "NostrandCore"),
        .executableTarget(
            name: "NostrandMenuBar",
            dependencies: ["NostrandCore"]
        ),
        .testTarget(
            name: "NostrandCoreTests",
            dependencies: ["NostrandCore"]
        )
    ]
)
