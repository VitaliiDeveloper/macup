// swift-tools-version:5.9
import PackageDescription

// Foundation only: no third-party packages (docs/swift-port-plan.md).
let package = Package(
    name: "macup",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacupCore", path: "Sources/MacupCore"),
        // Sources/macup/Generated is written by build.sh: the translations
        .executableTarget(name: "macup", dependencies: ["MacupCore"], path: "Sources/macup"),
        // tests/, not Tests/: one folder on a case-insensitive disk. Fixtures are read from the checkout (Checkout.fixture).
        .testTarget(name: "MacupCoreTests", dependencies: ["MacupCore", "macup"], path: "tests/MacupCoreTests", exclude: ["Fixtures"]),
    ]
)
