// swift-tools-version:5.9
import PackageDescription

// The native Laya runtime: ModernBERT-large + the decision head in MLX,
// exposed as a C ABI dylib for dart:ffi. Ports laya_mlx/model.py
// (github.com/mizorewww/laya-mlx, Apache-2.0) to MLX Swift.
let package = Package(
    name: "LayaNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LayaNative", type: .dynamic, targets: ["LayaNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.14.0")
    ],
    targets: [
        .target(
            name: "LayaNative",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
            ],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
