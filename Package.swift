// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Grabby",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Grabby", path: "Sources/Grabby")
    ]
)
