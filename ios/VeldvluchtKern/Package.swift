// swift-tools-version:5.9
// The app's plain-Swift core: route file, route checks and the field data formats.
// No DJI, UIKit or MapKit code, so `swift test` runs it on the Mac without a simulator.
// The app compiles the same source files directly (see Veldvlucht.xcodeproj, group "Kern").
import PackageDescription

let package = Package(
    name: "VeldvluchtKern",
    platforms: [.macOS(.v13), .iOS(.v16)],
    targets: [
        .target(name: "VeldvluchtKern", path: "Sources/VeldvluchtKern"),
        .testTarget(
            name: "VeldvluchtKernTests",
            dependencies: ["VeldvluchtKern"],
            path: "Tests/VeldvluchtKernTests"
        ),
    ]
)
