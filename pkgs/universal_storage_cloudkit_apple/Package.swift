// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "universal_storage_cloudkit_apple_support",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "CloudKitAppleSupport",
      targets: ["CloudKitAppleSupport"]
    ),
  ],
  targets: [
    .target(
      name: "CloudKitAppleSupport",
      path: "ios/Classes",
      exclude: [
        "CloudKitAppleApi.g.swift",
        "UniversalStorageCloudKitApplePlugin.swift",
      ],
      sources: ["CloudKitAppleSupport.swift"]
    ),
    .testTarget(
      name: "CloudKitAppleSupportTests",
      dependencies: ["CloudKitAppleSupport"],
      path: "swift_tests/Tests"
    ),
  ]
)
