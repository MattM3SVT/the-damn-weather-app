// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeatherShared",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "WeatherShared", targets: ["WeatherShared"]),
    ],
    targets: [
        .target(
            name: "WeatherShared",
            resources: [
                .process("Resources/phrases-clean.json"),
                .process("Resources/phrases-explicit.json"),
            ]
        ),
    ]
)
