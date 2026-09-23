// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "STTSCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "STTSCore", targets: ["STTSCore"])
    ],
    targets: [
        .target(name: "STTSCore"),
        .testTarget(name: "STTSCoreTests", dependencies: ["STTSCore"])
    ],
    swiftLanguageModes: [.v6]
)
