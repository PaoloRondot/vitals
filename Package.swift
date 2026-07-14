// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SensorShims"),
        .executableTarget(
            name: "Vitals",
            dependencies: ["SensorShims"],
            linkerSettings: [
                .linkedLibrary("IOReport"),
                .linkedFramework("IOKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
