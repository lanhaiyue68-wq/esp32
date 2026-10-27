// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "PointerMotionChecks", products: [], targets: [
    .target(name: "PointerMotion", path: "Sources"),
    .testTarget(name: "PointerMotionTests", dependencies: ["PointerMotion"], path: "Tests")
])
