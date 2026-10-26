// swift-tools-version: 5.9
import PackageDescription

let package = Package(name: "CapturePolicy", targets: [
    .target(name: "CapturePolicy", path: "Sources"),
    .testTarget(name: "CapturePolicyTests", dependencies: ["CapturePolicy"], path: "Tests")
])
