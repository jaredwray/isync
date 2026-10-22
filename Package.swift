// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "isync",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ISyncCore", targets: ["ISyncCore"])
    ],
    targets: [
        // Linux only. The Apple SDKs supply their own SQLite3 module.
        .systemLibrary(
            name: "CSQLite",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "ISyncCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ]
        ),
        .testTarget(
            name: "ISyncCoreTests",
            dependencies: ["ISyncCore"]
        ),
    ]
)
