// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoreTemp",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "CoreTempKit", dependencies: ["CSMC"]),
        .executableTarget(name: "CoreTemp", dependencies: ["CoreTempKit"]),
        .executableTarget(name: "coretemp-helper", dependencies: ["CoreTempKit"], path: "Sources/Helper"),
    ]
)
