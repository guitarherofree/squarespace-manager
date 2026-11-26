// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiteKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SiteKit", targets: ["SiteKit"])
    ],
    targets: [
        .target(name: "SiteKit"),
        .testTarget(name: "SiteKitTests", dependencies: ["SiteKit"])
    ]
)
