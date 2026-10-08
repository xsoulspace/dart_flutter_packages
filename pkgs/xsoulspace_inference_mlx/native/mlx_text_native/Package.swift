// swift-tools-version:6.0
import PackageDescription

// The native MLX text runtime: general small-LLM generation over
// ml-explore/mlx-swift-lm (MLXLLM/MLXLMCommon), exposed as a C ABI dylib
// for dart:ffi. All generation machinery — model registry, tokenizers +
// chat templates (swift-transformers), KV cache, samplers — is
// library-provided; this package adds only the ABI shim. The target keeps
// the Swift 5 language mode: the semaphore-bridged async load/generate
// boundary is deliberately simple, not actor-refined.
let package = Package(
    name: "MlxTextNative",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MlxTextNative", type: .dynamic, targets: ["MlxTextNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.32.3"),
        // Named directly: the shim imports MLX (MLXArray) from the core.
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.14.0"),
        // 3.x decoupled these from MLXLLM — name them explicitly.
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "MlxTextNative",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
