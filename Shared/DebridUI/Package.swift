// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DebridUI",
    platforms: [.iOS(.v18), .tvOS(.v18), .macOS(.v14)],
    products: [.library(name: "DebridUI", targets: ["DebridUI"])],
    dependencies: [
        .package(path: "../../Packages/DebridCore"),
        .package(url: "https://github.com/alexeichhorn/YouTubeKit", from: "0.4.8"),
    ],
    targets: [
        .target(name: "DebridUI", dependencies: [
            .product(name: "DebridCore", package: "DebridCore"),
            .product(name: "YouTubeKit", package: "YouTubeKit"),
        ]),
        .testTarget(name: "DebridUITests", dependencies: ["DebridUI"]),
    ]
)
