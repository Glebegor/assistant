// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RightHand",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Whisper speech recognition on the Mac (Core ML / Neural Engine), for meeting recordings.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "RightHand",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
            path: "Sources/RightHand"
        )
    ]
)
