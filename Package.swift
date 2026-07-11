// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QMDMenuBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "QMDMenuBar",
            targets: ["QMDMenuBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "QMDMenuBar",
            path: "Sources/QMDMenuBar",
            resources: [
                .copy("Resources/AppIcon.png"),
                .copy("Resources/AppIcon.icns")
            ]
        ),
        .testTarget(
            name: "QMDMenuBarTests",
            dependencies: ["QMDMenuBar"],
            path: "Tests/QMDMenuBarTests"
        )
    ]
)
