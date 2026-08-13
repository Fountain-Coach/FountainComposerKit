// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "FountainComposerKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "FountainComposerCore", targets: ["FountainComposerCore"]),
        .library(name: "FountainComposerCloud", targets: ["FountainComposerCloud"]),
        .executable(name: "fountain-composer-cloud-server", targets: ["FountainComposerCloudServerExecutable"]),
        .library(name: "FountainComposerTestKit", targets: ["FountainComposerTestKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0")
    ],
    targets: [
        .target(name: "FountainComposerCore", dependencies: [
            .product(name: "Crypto", package: "swift-crypto")
        ]),
        .target(name: "FountainComposerCloud", dependencies: ["FountainComposerCore"]),
        .executableTarget(name: "FountainComposerCloudServerExecutable", dependencies: ["FountainComposerCloud"]),
        .target(name: "FountainComposerTestKit", dependencies: ["FountainComposerCore"]),
        .testTarget(name: "FountainComposerKitTests", dependencies: ["FountainComposerCore", "FountainComposerCloud", "FountainComposerTestKit"])
    ]
)
