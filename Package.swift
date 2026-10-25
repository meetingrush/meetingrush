// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MeetingRush",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingRush", targets: ["MeetingRush"]),
    ],
    targets: [
        .target(name: "MeetingRushCore"),
        .executableTarget(name: "MeetingRush", dependencies: ["MeetingRushCore"]),
        .testTarget(name: "MeetingRushCoreTests", dependencies: ["MeetingRushCore"]),
    ]
)
