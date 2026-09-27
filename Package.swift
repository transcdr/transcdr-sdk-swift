// swift-tools-version:5.10
import PackageDescription

// TranscdrKit: the Transcdr API client and the app's platform-neutral logic
// (models, formatting, the output-spec and integration catalogs). It builds
// on Apple platforms and on Linux, so its tests run without a Mac.
let package = Package(
    name: "TranscdrKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TranscdrKit", targets: ["TranscdrKit"]),
    ],
    targets: [
        .target(name: "TranscdrKit"),
        .testTarget(name: "TranscdrKitTests", dependencies: ["TranscdrKit"], resources: [.copy("Fixtures")]),
    ]
)
