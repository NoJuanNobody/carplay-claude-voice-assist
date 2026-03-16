// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CarPlayAssistant",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CarPlayAssistant",
            targets: ["CarPlayAssistant"]
        ),
        .library(
            name: "CarPlayUI",
            targets: ["CarPlayUI"]
        ),
    ],
    targets: [
        .target(
            name: "CarPlayAssistant",
            path: "Sources/CarPlayAssistant"
        ),
        .target(
            name: "CarPlayUI",
            dependencies: ["CarPlayAssistant"],
            path: "Sources/CarPlayUI"
        ),
        .testTarget(
            name: "CarPlayAssistantTests",
            dependencies: ["CarPlayAssistant"],
            path: "Tests/CarPlayAssistantTests"
        ),
    ]
)
