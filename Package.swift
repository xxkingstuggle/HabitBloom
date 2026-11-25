// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HabitBloom",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "HabitCore", targets: ["HabitCore"]),
        .library(name: "HabitWidgetShared", targets: ["HabitWidgetShared"]),
        .executable(name: "HabitCoreSmokeTests", targets: ["HabitCoreSmokeTests"]),
        .executable(name: "HabitCoreStressTests", targets: ["HabitCoreStressTests"])
    ],
    targets: [
        .target(name: "HabitCore"),
        .target(name: "HabitWidgetShared"),
        .executableTarget(name: "HabitCoreSmokeTests", dependencies: ["HabitCore", "HabitWidgetShared"]),
        .executableTarget(name: "HabitCoreStressTests", dependencies: ["HabitCore", "HabitWidgetShared"])
    ]
)
