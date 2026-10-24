// swift-tools-version: 6.1
// Tools 6.1 is the floor for this manifest, because SwiftText is added with
// `traits:`. The toolchain must be Swift 6.3 or later: SwiftText's manifest is tools 6.3.
import PackageDescription

let package = Package(
    name: "iris",
    platforms: [
        // SwiftMail and the swift-nio-imap revision it pins need macOS 15.
        .macOS(.v15)
    ],
    products: [
        .library(name: "IrisKit", targets: ["IrisKit"]),
        .executable(name: "iris", targets: ["iris"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        // SwiftMail pins swift-nio-imap by revision, so SwiftPM cannot resolve
        // SwiftMail by version. Pin a release's commit and bump it by hand.
        // 88c45cbd is the 1.16.0 tag.
        .package(url: "https://github.com/Cocoanetics/SwiftMail", revision: "88c45cbd31b347b373f7c87e197be63eb95efbc2"),
        // The HTML trait gives HTML-to-Markdown without SwiftText's PDF/OCR parts.
        .package(url: "https://github.com/Cocoanetics/SwiftText", from: "2.4.0", traits: ["HTML"]),
        // SwiftMail logs through swift-log. Only the executable picks the backend.
        .package(url: "https://github.com/apple/swift-log", from: "1.6.0"),
    ],
    targets: [
        // The library holds all logic and never prints: it logs through the
        // IrisLog seam. Only the executable parses arguments and writes output.
        .target(
            name: "IrisKit",
            dependencies: [
                .product(name: "SwiftMail", package: "SwiftMail"),
                .product(name: "SwiftTextHTML", package: "SwiftText"),
            ]
        ),
        .executableTarget(
            name: "iris",
            dependencies: [
                "IrisKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .testTarget(name: "IrisKitTests", dependencies: ["IrisKit"]),
        .testTarget(name: "CLITests", dependencies: ["iris"]),
    ]
)
