// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "isar_plus_flutter_libs",
    platforms: [
        .iOS(.v11),
        .macOS(.v10_13),
    ],
    products: [
        .library(
            name: "isar-plus-flutter-libs",
            targets: ["isar_plus_flutter_libs"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "isar_plus_core",
            url: "https://github.com/bymoye/isar_plus/releases/download/1.3.6/isar_plus_core.xcframework.zip",
            checksum: "e82628ce297a4e0beafe681f29d58f56a84bb08a41108646bde065337a2f1592"
        ),
        .target(
            name: "CIsarCore",
            dependencies: ["isar_plus_core"],
            path: "Core",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-all_load"], .when(platforms: [.iOS, .macOS]))
            ]
        ),
        .target(
            name: "isar_plus_flutter_libs",
            dependencies: ["CIsarCore"],
            path: "Plugin",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-all_load"], .when(platforms: [.iOS, .macOS]))
            ]
        ),
    ]
)
