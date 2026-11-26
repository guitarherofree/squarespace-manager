import Foundation
import XCTest
@testable import GitHubReleaseUpdater

final class UpdaterTests: XCTestCase {
    let configuration = UpdaterConfiguration(
        repository: "guitarherofree/squarespace-manager",
        appName: "Website",
        currentVersion: "0.2.0",
        bundleIdentifier: "com.freemanedwards.Website"
    )

    func testVersionComparison() {
        XCTAssertTrue(VersionComparison.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(VersionComparison.isNewer("v1.0", than: "0.99.1"))
        XCTAssertFalse(VersionComparison.isNewer("0.2.0", than: "0.2"))
        XCTAssertFalse(VersionComparison.isNewer("0.2.0-beta", than: "0.2.0"))
        XCTAssertEqual(VersionComparison.compare("1.2.3", "1.2.4"), .orderedAscending)
    }

    func testAssetName() {
        XCTAssertEqual(configuration.assetName(for: "0.3.0"), "Website-0.3.0-mac-arm64.zip")
    }

    func testDecodesReleaseAndPicksAsset() throws {
        let json = """
        {
          "tag_name": "v0.3.0", "name": "Website 0.3.0", "body": "- Things",
          "html_url": "https://github.com/x/y/releases/tag/v0.3.0",
          "draft": false, "prerelease": false, "published_at": "2026-11-26T15:00:00Z",
          "assets": [
            {"name": "notes.txt", "size": 3, "url": "https://api.github.com/a/1",
             "browser_download_url": "https://github.com/x/y/releases/download/v0.3.0/notes.txt"},
            {"name": "Website-0.3.0-mac-arm64.zip", "size": 1000, "url": "https://api.github.com/a/2",
             "browser_download_url": "https://github.com/x/y/releases/download/v0.3.0/Website-0.3.0-mac-arm64.zip",
             "digest": "sha256:ABCDEF"}
          ]
        }
        """
        let release = try GitHubRelease.decode(Data(json.utf8))
        XCTAssertEqual(release.version, "0.3.0")
        XCTAssertNotNil(release.publishedAt)
        let asset = try XCTUnwrap(release.asset(for: configuration))
        XCTAssertEqual(asset.name, "Website-0.3.0-mac-arm64.zip")
        XCTAssertEqual(asset.sha256, "abcdef")
        XCTAssertEqual(asset.apiURL.absoluteString, "https://api.github.com/a/2")
    }

    func testFallsBackToAnyMacZip() throws {
        let json = """
        {"tag_name": "1.0.0", "draft": false, "prerelease": false, "assets": [
          {"name": "Website-mac-arm64.zip", "size": 1, "url": "https://api.github.com/a/3",
           "browser_download_url": "https://github.com/x/y/w.zip"}]}
        """
        let release = try GitHubRelease.decode(Data(json.utf8))
        XCTAssertEqual(release.asset(for: configuration)?.name, "Website-mac-arm64.zip")
    }

    func testSHA256OfFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("abc".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try GitHubUpdater.sha256(of: file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testInstallScriptIsValidBash() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("install-\(UUID().uuidString).sh")
        try GitHubUpdater.installScript.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try await GitHubUpdater.run("/bin/bash", ["-n", file.path])
        XCTAssertEqual(result.status, 0, result.output)
    }

    func testInstallSwapsAppAndKeepsPrevious() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let current = root.appendingPathComponent("Applications/Website.app", isDirectory: true)
        let staged = root.appendingPathComponent("Updates/0.3.0/unpacked/Website.app", isDirectory: true)
        let previous = root.appendingPathComponent("Updates/Previous/Website.app", isDirectory: true)
        let log = root.appendingPathComponent("update.log")
        for (folder, marker) in [(current, "old"), (staged, "new")] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(marker.utf8).write(to: folder.appendingPathComponent("marker"))
        }
        try FileManager.default.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
        let script = root.appendingPathComponent("install.sh")
        try GitHubUpdater.installScript.write(to: script, atomically: true, encoding: .utf8)
        // PID 999999 doesn't exist, so the script doesn't wait.
        let result = try await GitHubUpdater.run("/bin/bash", [script.path, "999999", staged.path, current.path, previous.path, "0", log.path])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(try String(contentsOf: current.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertEqual(try String(contentsOf: previous.appendingPathComponent("marker"), encoding: .utf8), "old")
    }
}
