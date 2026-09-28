// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DocumentEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocumentEngine", targets: ["DocumentEngine"])
    ],
    dependencies: [
        .package(path: "../../ConversionKit")
    ],
    targets: [
        .target(name: "DocumentEngine", dependencies: ["ConversionKit"]),
        .testTarget(name: "DocumentEngineTests", dependencies: ["DocumentEngine"]),
    ]
)
