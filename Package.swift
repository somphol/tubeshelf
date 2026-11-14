// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TubeShelf",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TubeShelf", targets: ["TubeShelf"]),
        .executable(name: "tubeshelf-check", targets: ["TubeShelfCheck"]),
        .library(name: "TubeShelfCore", targets: ["TubeShelfCore"])
    ],
    targets: [
        .target(
            name: "TubeShelfCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "TubeShelf",
            dependencies: ["TubeShelfCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "TubeShelfCheck",
            dependencies: ["TubeShelfCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TubeShelfCoreTests",
            dependencies: ["TubeShelfCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
