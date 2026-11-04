// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-or-later

import PackageDescription

let package = Package(
    name: "SpaceroomCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpaceroomCore", targets: ["SpaceroomCore"]),
    ],
    targets: [
        // Library code is deliberately `nonisolated` (no default main-actor isolation):
        // callers decide where work runs.
        .target(
            name: "SpaceroomCore",
            resources: [.copy("Resources/Rules")]
        ),
        .testTarget(
            name: "SpaceroomCoreTests",
            dependencies: ["SpaceroomCore"]
        ),
    ]
)
