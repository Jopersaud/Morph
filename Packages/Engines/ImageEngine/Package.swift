// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ImageEngine", targets: ["ImageEngine"])
    ],
    dependencies: [
        .package(path: "../../ConversionKit")
    ],
    targets: [
        .target(name: "ImageEngine", dependencies: ["ConversionKit"]),
        .testTarget(name: "ImageEngineTests", dependencies: ["ImageEngine"]),
    ]
)
