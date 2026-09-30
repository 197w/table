// swift-tools-version: 5.9
// Kurs dostawcy w CarPlay dla Table for employees.

import PackageDescription

let package = Package(
    name: "table_car",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "table-car", targets: ["table_car"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "table_car",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("CarPlay")
            ]
        )
    ]
)
