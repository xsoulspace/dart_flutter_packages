// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "xsoulspace_monetization_google_apple",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "xsoulspace-monetization-google-apple",
            targets: ["xsoulspace_monetization_google_apple"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "xsoulspace_monetization_google_apple",
            dependencies: [],
            path: "Sources/xsoulspace_monetization_google_apple"
        )
    ]
)
