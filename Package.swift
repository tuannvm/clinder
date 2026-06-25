// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "clinder",
    platforms: [
        .macOS(.v27)
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
