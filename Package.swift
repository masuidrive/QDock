// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "QDock",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "QDock",
            path: "UsageBar",
            exclude: [
                "Resources/Info.plist",
                "Resources/IconExports"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
