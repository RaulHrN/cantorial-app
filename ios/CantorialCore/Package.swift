// swift-tools-version:5.9
import PackageDescription

// Audio and music logic of Cantorial, shared by the iOS app and its tests.
// It mirrors the Kotlin package app/src/main/java/com/raulhrn/vox/core of the Android app.
let package = Package(
    name: "CantorialCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CantorialCore", targets: ["CantorialCore"]),
        .library(name: "CantorialAtomics", targets: ["CantorialAtomics"]),
    ],
    targets: [
        .target(name: "CantorialCore", resources: [.process("Resources")]),
        .target(name: "CantorialAtomics"),
        .testTarget(name: "CantorialCoreTests", dependencies: ["CantorialCore"]),
    ]
)
