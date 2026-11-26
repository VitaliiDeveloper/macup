// swift-tools-version:5.9
import PackageDescription

// Foundation only: no third-party packages (docs/swift-port-plan.md).
let package = Package(
    name: "macup",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacupCore", path: "Sources/MacupCore"),
        // Sources/macup/Generated is written by build.sh: the bash build and the translations
        .executableTarget(name: "macup", dependencies: ["MacupCore"], path: "Sources/macup"),
        .testTarget(name: "MacupCoreTests", dependencies: ["MacupCore", "macup"], path: "tests/MacupCoreTests"),   // tests/, not Tests/: one folder on a case-insensitive disk
    ]
)
