// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SunCore",
    // macOS is listed so `swift test` runs on the host Mac without a simulator.
    platforms: [.iOS(.v26), .macOS(.v14), .watchOS(.v26)],
    products: [
        .library(name: "SunCore", targets: ["SunCore"]),
    ],
    targets: [
        .target(name: "SunCore"),
        .testTarget(name: "SunCoreTests", dependencies: ["SunCore"]),
    ]
)
