// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridCore",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [
        .library(name: "DebridCore", targets: ["DebridCore"]),
    ],
    targets: [
        .target(name: "DebridCore"),
        .testTarget(name: "DebridCoreTests", dependencies: ["DebridCore"]),
    ]
)
