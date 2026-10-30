// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Luksfer",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Luksfer", targets: ["Luksfer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // File system logic with no UI: listing, sorting, paths, file operations, undo.
        .target(name: "LuksferCore"),
        // The app (AppKit).
        .executableTarget(
            name: "Luksfer",
            dependencies: ["LuksferCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        // Spike benchmarks and checks (docs/spike-report.md). Run: swift run LuksferSpike <check>
        .executableTarget(
            name: "LuksferSpike",
            dependencies: ["LuksferCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Spike"
        ),
        .testTarget(name: "LuksferCoreTests", dependencies: ["LuksferCore"]),
    ],
    swiftLanguageModes: [.v5]
)
