// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QLaunch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QLaunch", targets: ["QLaunch"])
    ],
    targets: [
        .executableTarget(
            name: "QLaunch"
        ),
        .testTarget(
            name: "QLaunchTests",
            dependencies: ["QLaunch"]
        ),
    ]
)
