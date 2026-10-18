// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RightHand",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "RightHand",
            path: "Sources/RightHand"
        )
    ]
)
