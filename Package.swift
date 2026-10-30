// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Okno",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Okno", targets: ["Okno"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        // File system logic with no UI: listing, sorting, paths, file operations, undo.
        .target(name: "OknoCore"),
        // The app (AppKit).
        .executableTarget(
            name: "Okno",
            dependencies: ["OknoCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        // Spike benchmarks and checks. Run: swift run OknoSpike <check>
        .executableTarget(
            name: "OknoSpike",
            dependencies: ["OknoCore", .product(name: "SwiftTerm", package: "SwiftTerm")],
            path: "Spike"
        ),
        .testTarget(name: "OknoCoreTests", dependencies: ["OknoCore"]),
    ],
    swiftLanguageModes: [.v5]
)
