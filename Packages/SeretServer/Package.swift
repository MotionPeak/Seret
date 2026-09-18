// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SeretServer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../DebridCore"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.106.0"),
        // Already in the graph via Vapor; declared here because the CDP transport uses it directly.
        // Chrome's DevTools writes headers with no space after the colon, which Foundation's Linux
        // URLSession refuses to parse, and NIO's parser accepts.
        .package(url: "https://github.com/swift-server/async-http-client.git", from: "1.36.0"),
    ],
    targets: [
        .executableTarget(
            name: "SeretServer",
            dependencies: [
                .product(name: "DebridCore", package: "DebridCore"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
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
