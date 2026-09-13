// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NativeTelemetryCore",
    platforms: [
        .iOS("15.0"),
        .macOS("12.0"),
    ],
    products: [
        .library(name: "NativeTelemetryCore", targets: ["NativeTelemetryCore"]),
    ],
    targets: [
        .target(name: "NativeTelemetryCore"),
        .testTarget(
            name: "NativeTelemetryCoreTests",
            dependencies: ["NativeTelemetryCore"]
        ),
    ]
)
