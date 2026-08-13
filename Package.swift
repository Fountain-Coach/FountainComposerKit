// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainComposerKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FountainComposerCore", targets: ["FountainComposerCore"]),
        .library(name: "FountainComposerTestKit", targets: ["FountainComposerTestKit"])
    ],
    targets: [
        .target(name: "FountainComposerCore"),
        .target(name: "FountainComposerTestKit", dependencies: ["FountainComposerCore"]),
        .testTarget(name: "FountainComposerKitTests", dependencies: ["FountainComposerCore", "FountainComposerTestKit"])
    ]
)
