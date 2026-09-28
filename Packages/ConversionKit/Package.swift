// swift-tools-version: 6.0
// swift-tools-version 6.0 puts every target in the Swift 6 language mode, so
// complete concurrency checking is on without extra settings.
import PackageDescription

let package = Package(
    name: "ConversionKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ConversionKit", targets: ["ConversionKit"])
    ],
    targets: [
        .target(name: "ConversionKit"),
        .testTarget(name: "ConversionKitTests", dependencies: ["ConversionKit"]),
    ]
)
