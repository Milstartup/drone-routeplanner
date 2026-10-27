// swift-tools-version:5.9
// The app's plain-Swift core: route file, route checks and the field data formats.
// No DJI, UIKit or MapKit code, so `swift test` runs it on the Mac without a simulator.
// The app compiles the same source files directly (see Veldvlucht.xcodeproj, group "Kern").
// The Mac tool foto-analyse uses it too.
import PackageDescription

let package = Package(
    name: "VeldvluchtKern",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        // The photo analysis on the Mac: swift run --package-path ios/VeldvluchtKern foto-analyse <map>
        .executable(name: "foto-analyse", targets: ["FotoAnalyse"]),
    ],
    targets: [
        .target(name: "VeldvluchtKern", path: "Sources/VeldvluchtKern"),
        .executableTarget(name: "FotoAnalyse", dependencies: ["VeldvluchtKern"], path: "Sources/FotoAnalyse"),
        .testTarget(
            name: "VeldvluchtKernTests",
            dependencies: ["VeldvluchtKern"],
            path: "Tests/VeldvluchtKernTests",
            // An answer of the Open-Meteo API, read by the tests through its path.
            exclude: ["open-meteo-voorbeeld.json"]
        ),
    ]
)
