// swift-tools-version: 6.0
import PackageDescription
import Foundation

let sparkleTestFrameworks = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent(".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64").path

let package = Package(
    name: "PerformanceDaddy",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerformanceCore", targets: ["PerformanceCore"]),
        .executable(name: "PerformanceDaddy", targets: ["PerformanceDaddy"]),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"), .package(url: "https://github.com/sass-maker/ui-library", from: "0.1.14")],
    targets: [
        .target(name: "NativeInspection"),
        .target(name: "PerformanceCore", dependencies: ["NativeInspection"]),
        .executableTarget(
            name: "PerformanceDaddy",
            dependencies: [.product(name: "SaaSMakerUI", package: "ui-library"), "PerformanceCore", "NativeInspection", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PerformanceCoreTests",
            dependencies: ["PerformanceCore"]
        ),
        .testTarget(name: "PerformanceDaddyTests", dependencies: ["PerformanceDaddy"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sparkleTestFrameworks])]),
    ]
)
