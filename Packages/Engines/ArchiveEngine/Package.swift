// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ArchiveEngine",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchiveEngine", targets: ["ArchiveEngine"])
    ],
    dependencies: [
        .package(path: "../../ConversionKit")
    ],
    targets: [
        .target(name: "ArchiveEngine", dependencies: ["ConversionKit"]),
        .testTarget(name: "ArchiveEngineTests", dependencies: ["ArchiveEngine"]),
    ]
)
