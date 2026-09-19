// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShotStash",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ShotStashCore"),
        .executableTarget(
            name: "ShotStash",
            dependencies: ["ShotStashCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "ShotStashCoreTests", dependencies: ["ShotStashCore"]),
    ],
    swiftLanguageVersions: [.v5]
)
