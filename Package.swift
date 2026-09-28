// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Awake",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Awake", targets: ["Awake"]),
    ],
    targets: [
        .executableTarget(
            name: "Awake",
            dependencies: ["AwakeKit"]
        ),
        .target(
            name: "AwakeKit",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "AwakeKitTests",
            dependencies: ["AwakeKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
