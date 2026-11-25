// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vitals",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VitalsCore", path: "Sources/VitalsCore"),
        .executableTarget(name: "Vitals", dependencies: ["VitalsCore"], path: "Sources/Vitals"),
        .testTarget(name: "VitalsCoreTests", dependencies: ["VitalsCore"], path: "Tests/VitalsCoreTests")
    ]
)
