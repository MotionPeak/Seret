// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeretServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../DebridCore"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
    ],
    targets: [
        .executableTarget(
            name: "SeretServer",
            dependencies: [
                .product(name: "DebridCore", package: "DebridCore"),
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "SeretServerTests",
            dependencies: [
                .target(name: "SeretServer"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
