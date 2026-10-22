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

// The app, its macOS adapters, and the command-line tool use Apple frameworks
// (Contacts, Security, ServiceManagement, SwiftUI). Linux builds the core only.
#if os(macOS)
    package.products += [
        .executable(name: "ISyncApp", targets: ["ISyncApp"]),
        .executable(name: "isync-cli", targets: ["isync-cli"]),
    ]
    package.targets += [
        .target(name: "ISyncMac", dependencies: ["ISyncCore"]),
        .executableTarget(name: "ISyncApp", dependencies: ["ISyncCore", "ISyncMac"]),
        .executableTarget(name: "isync-cli", dependencies: ["ISyncCore", "ISyncMac"]),
        .testTarget(name: "ISyncMacTests", dependencies: ["ISyncCore", "ISyncMac"]),
    ]
#endif
