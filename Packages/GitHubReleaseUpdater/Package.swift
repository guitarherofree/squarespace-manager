// swift-tools-version:5.9
import PackageDescription

// The standard in-app updater for Freeman's Mac apps: checks the repository's latest
// GitHub release, downloads <AppName>-<version>-mac-arm64.zip, verifies it, swaps the
// app bundle after quitting and reopens it. No signing keys or secrets; a read-only
// token is needed only when the repository is private.
let package = Package(
    name: "GitHubReleaseUpdater",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "GitHubReleaseUpdater", targets: ["GitHubReleaseUpdater"])
    ],
    targets: [
        .target(name: "GitHubReleaseUpdater"),
        .testTarget(name: "GitHubReleaseUpdaterTests", dependencies: ["GitHubReleaseUpdater"])
    ]
)
