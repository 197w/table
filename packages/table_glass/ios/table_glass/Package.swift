// swift-tools-version: 5.9
// Natywne przyciski Liquid Glass nad widokiem Fluttera.

import PackageDescription

let package = Package(
    name: "table_glass",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "table-glass", targets: ["table_glass"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "table_glass",
            dependencies: []
        )
    ]
)
