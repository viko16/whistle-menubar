// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "whistle-menubar",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "whistle-menubar", targets: ["WhistleMenuBarApp"]),
        .executable(name: "whistle-menubar-tests", targets: ["WhistleMenuBarSelfTests"]),
        .library(name: "WhistleMenuBarCore", targets: ["WhistleMenuBarCore"])
    ],
    targets: [
        .target(
            name: "WhistleMenuBarCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "WhistleMenuBarApp",
            dependencies: ["WhistleMenuBarCore"]
        ),
        .executableTarget(
            name: "WhistleMenuBarSelfTests",
            dependencies: ["WhistleMenuBarCore"]
        )
    ]
)
