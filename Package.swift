// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iris",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "IrisKit", targets: ["IrisKit"]),
        .executable(name: "iris", targets: ["iris"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        // The library holds all logic and never prints: it logs through the
        // IrisLog seam. Only the executable parses arguments and writes output.
        .target(name: "IrisKit"),
        .executableTarget(
            name: "iris",
            dependencies: [
                "IrisKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "IrisKitTests", dependencies: ["IrisKit"]),
        .testTarget(name: "CLITests", dependencies: ["iris"]),
    ]
)
