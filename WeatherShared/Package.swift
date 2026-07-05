// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WeatherShared",
    // Match the app targets' IPHONEOS_DEPLOYMENT_TARGET so availability
    // checking inside the package reflects what actually ships. watchOS is
    // declared so the (planned) Watch app target can depend on this package.
    platforms: [.iOS("26.0"), .watchOS("26.0")],
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
        .testTarget(
            name: "WeatherSharedTests",
            dependencies: ["WeatherShared"]
        ),
    ]
)
