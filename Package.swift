// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "clinder",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Clinder", targets: ["Clinder"])
    ],
    targets: [
        .executableTarget(
            name: "Clinder",
            path: "Sources/Clinder"
        )
    ]
)
