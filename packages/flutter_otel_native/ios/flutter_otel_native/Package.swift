// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_otel_native",
    platforms: [.iOS("15.0")],
    products: [
        .library(name: "flutter-otel-native", targets: ["flutter_otel_native"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(path: "../../native/NativeTelemetryCore"),
    ],
    targets: [
        .target(
            name: "flutter_otel_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "NativeTelemetryCore", package: "NativeTelemetryCore"),
            ]
        ),
    ]
)
