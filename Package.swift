// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DrillCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "DrillCore", targets: ["DrillCore"])],
    targets: [
        .target(name: "DrillCore", path: "Sources/DrillCore"),
        .testTarget(name: "DrillCoreTests", dependencies: ["DrillCore"], path: "Tests/DrillCoreTests", resources: [.copy("Fixtures")]),
    ]
)
