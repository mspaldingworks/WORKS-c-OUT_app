// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WorksCoutCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "WorksCoutCore", targets: ["WorksCoutCore"]),
    ],
    targets: [
        .target(name: "WorksCoutCore"),
        .testTarget(name: "WorksCoutCoreTests", dependencies: ["WorksCoutCore"]),
    ]
)
