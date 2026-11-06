// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "KSlides", platforms: [.macOS(.v15)], products: [
    .executable(name: "KSlides", targets: ["KSlides"]),
    .executable(name: "KSlidesMCP", targets: ["KSlidesMCP"])
], targets: [
    .target(name: "KSlidesCore"),
    .executableTarget(name: "KSlides", dependencies: ["KSlidesCore"]),
    .executableTarget(name: "KSlidesMCP", dependencies: ["KSlidesCore"]),
    .executableTarget(name: "KSlidesChecks", dependencies: ["KSlidesCore"], path: "Tests/KSlidesCoreTests")
])
