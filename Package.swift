// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniTherm",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "MiniThermKit", dependencies: ["CSMC"]),
        .executableTarget(name: "MiniTherm", dependencies: ["MiniThermKit"]),
        .executableTarget(name: "minitherm-helper", dependencies: ["MiniThermKit"], path: "Sources/Helper"),
    ]
)
