// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ZayFlowCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ZayFlowCore", targets: ["ZayFlowCore"])
    ],
    targets: [
        .target(
            name: "ZayFlowCore",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ZayFlowCoreTests",
            dependencies: ["ZayFlowCore"]
        )
    ]
)
