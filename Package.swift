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
        .executable(name: "HabitCoreSmokeTests", targets: ["HabitCoreSmokeTests"]),
        .executable(name: "HabitCoreStressTests", targets: ["HabitCoreStressTests"])
    ],
    targets: [
        .target(name: "HabitCore"),
        .executableTarget(name: "HabitCoreSmokeTests", dependencies: ["HabitCore"]),
        .executableTarget(name: "HabitCoreStressTests", dependencies: ["HabitCore"])
    ]
)
