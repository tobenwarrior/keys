// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "keys",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "keys", targets: ["keys"])
    ],
    targets: [
        .target(name: "KeysCore"),
        .executableTarget(name: "keys", dependencies: ["KeysCore"]),
        .testTarget(name: "KeysCoreTests", dependencies: ["KeysCore"])
    ]
)
