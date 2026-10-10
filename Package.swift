// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenFocusIsland",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FocusCore", targets: ["FocusCore"]),
        .executable(name: "OpenFocusIsland", targets: ["OpenFocusIsland"]),
    ],
    targets: [
        .target(name: "FocusCore"),
        .executableTarget(name: "OpenFocusIsland", dependencies: ["FocusCore"]),
        .testTarget(name: "FocusCoreTests", dependencies: ["FocusCore"]),
        .testTarget(name: "FocusAppTests", dependencies: ["OpenFocusIsland", "FocusCore"]),
    ]
)
