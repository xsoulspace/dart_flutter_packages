// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "xsoulspace_inference_apple_foundation",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(
            name: "xsoulspace-inference-apple-foundation",
            targets: ["xsoulspace_inference_apple_foundation"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "xsoulspace_inference_apple_foundation",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            linkerSettings: [
                .linkedFramework("FoundationModels")
            ]
        )
    ]
)
