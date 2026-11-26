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
        .library(name: "PerformanceWorkspaceKit", targets: ["PerformanceWorkspaceKit"]),
        .executable(name: "PerformanceDaddy", targets: ["PerformanceDaddyLauncher"]),
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"), .package(url: "https://github.com/sass-maker/ui-library", revision: "f45faf3eb04af08cff2022710c8b8157a60bf5fa")],
    targets: [
        .target(name: "NativeInspection", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "PerformanceCore", dependencies: ["NativeInspection"]),
        .target(
            name: "PerformanceDaddy",
            dependencies: [.product(name: "SaaSMakerUI", package: "ui-library"), "PerformanceCore", "NativeInspection", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")]
        ),
        .target(name: "PerformanceWorkspaceKit", dependencies: ["PerformanceDaddy"]),
        .executableTarget(
            name: "PerformanceDaddyLauncher", dependencies: ["PerformanceDaddy"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "PerformanceCoreTests",
            dependencies: ["PerformanceCore"]
        ),
        .testTarget(name: "PerformanceDaddyTests", dependencies: ["PerformanceDaddy", "PerformanceWorkspaceKit"],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", sparkleTestFrameworks])]),
    ]
)
