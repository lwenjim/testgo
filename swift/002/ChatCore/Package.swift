// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatCore",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(name: "ChatCore", targets: ["ChatCore"])
    ],
    targets: [
        .target(name: "ChatCore")
    ]
)
