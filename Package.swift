// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MLXChat",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MLXChatCore",
            targets: ["MLXChatCore"]
        ),
        .executable(
            name: "mlxchat",
            targets: ["mlxchat"]
        ),
    ],
    targets: [
        .target(name: "MLXChatCore"),
        .executableTarget(
            name: "mlxchat",
            dependencies: ["MLXChatCore"]
        ),
        .testTarget(
            name: "MLXChatCoreTests",
            dependencies: ["MLXChatCore"]
        ),
    ]
)
