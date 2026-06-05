// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridUI",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [.library(name: "DebridUI", targets: ["DebridUI"])],
    dependencies: [.package(path: "../../Packages/DebridCore")],
    targets: [
        .target(name: "DebridUI", dependencies: [.product(name: "DebridCore", package: "DebridCore")]),
        .testTarget(name: "DebridUITests", dependencies: ["DebridUI"]),
    ]
)
