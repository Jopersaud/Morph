// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MorphIntents",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MorphIntents", targets: ["MorphIntents"])
    ],
    dependencies: [
        .package(path: "../ConversionKit")
    ],
    targets: [
        .target(name: "MorphIntents", dependencies: ["ConversionKit"]),
        .testTarget(name: "MorphIntentsTests", dependencies: ["MorphIntents"]),
    ]
)
