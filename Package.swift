// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CapacitorIcloudSync",
    platforms: [.iOS(.v14)],
    products: [
        .library(
            name: "CapacitorIcloudSync",
            targets: ["ICloudSyncPlugin"])
    ],
    dependencies: [
        .package(url: "https://github.com/ionic-team/capacitor-swift-pm.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "ICloudSyncPlugin",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Sources/ICloudSyncPlugin"),
        .testTarget(
            name: "ICloudSyncPluginTests",
            dependencies: ["ICloudSyncPlugin"],
            path: "ios/Tests/ICloudSyncPluginTests")
    ]
)
