// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "HexEvals",
  platforms: [.macOS(.v14)],
  products: [
    .library(name: "HexEvalSupport", targets: ["HexEvalSupport"]),
  ],
  dependencies: [
    .package(path: "../../HexCore"),
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
    .package(url: "https://github.com/ml-explore/mlx-swift-lm", .upToNextMajor(from: "3.31.3")),
    .package(url: "https://github.com/huggingface/swift-huggingface", from: "0.9.0"),
    .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.1.6"),
    .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "0.15.0"),
  ],
  targets: [
    .target(
      name: "HexEvalSupport",
      dependencies: [
        "HexCore",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm"),
        .product(name: "HuggingFace", package: "swift-huggingface"),
        .product(name: "Tokenizers", package: "swift-transformers"),
        .product(name: "WhisperKit", package: "WhisperKit"),
      ]
    ),
    .testTarget(
      name: "HexEvalsTests",
      dependencies: ["HexEvalSupport"]
    ),
  ]
)
