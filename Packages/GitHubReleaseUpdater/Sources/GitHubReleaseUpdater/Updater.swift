import CryptoKit
import Foundation

public enum UpdaterError: LocalizedError, Equatable {
    case noRelease
    case needsToken
    case badToken
    case rateLimited
    case http(Int)
    case noAsset(String)
    case checksumMismatch
    case wrongApp(String)
    case versionMismatch(expected: String, found: String)
    case signatureInvalid(String)
    case unzipFailed(String)
    case notInstallable(String)

    public var errorDescription: String? {
        switch self {
        case .noRelease:
            return "No release has been published yet."
        case .needsToken:
            return "GitHub didn't find the releases. If the repository is private, the app needs a read-only GitHub token."
        case .badToken:
            return "GitHub rejected the saved token (it may have expired). Add a new one in Settings › Updates."
        case .rateLimited:
            return "GitHub is limiting requests right now. The app will try again later."
        case .http(let status):
            return "GitHub answered with HTTP status \(status)."
        case .noAsset(let name):
            return "The latest release has no \(name) attached."
        case .checksumMismatch:
            return "The download doesn't match the checksum GitHub published, so it wasn't installed."
        case .wrongApp(let identifier):
            return "The download is a different app (\(identifier)), so it wasn't installed."
        case .versionMismatch(let expected, let found):
            return "The download is version \(found), not \(expected), so it wasn't installed."
        case .signatureInvalid(let detail):
            return "The downloaded app's code signature didn't verify: \(detail)"
        case .unzipFailed(let detail):
            return "The download couldn't be unpacked: \(detail)"
        case .notInstallable(let detail):
            return detail
        }
    }
}

/// Folders the updater uses: ~/Library/Application Support/<App>/Updates and ~/Library/Logs/<App>.
public struct UpdatePaths: Sendable {
    public let updatesFolder: URL
    public let previousVersion: URL
    public let logFile: URL

    public init(appName: String) {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let logs = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Logs", isDirectory: true)
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Logs")
        updatesFolder = support.appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        previousVersion = updatesFolder.appendingPathComponent("Previous", isDirectory: true)
            .appendingPathComponent("\(appName).app", isDirectory: true)
        logFile = logs.appendingPathComponent(appName, isDirectory: true).appendingPathComponent("update.log")
    }
}

public struct UpdateLog: Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public func write(_ message: String) {
        let formatter = ISO8601DateFormatter()
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        } else {
            try? Data(line.utf8).write(to: file)
        }
    }
}

/// Checks, downloads, verifies and installs releases. Holds no state, so it is safe to share.
public struct GitHubUpdater: Sendable {
    public let configuration: UpdaterConfiguration
    public let paths: UpdatePaths
    public let log: UpdateLog
    public var apiBase: URL

    public init(configuration: UpdaterConfiguration, apiBase: URL = URL(string: "https://api.github.com")!) {
        self.configuration = configuration
        self.paths = UpdatePaths(appName: configuration.appName)
        self.log = UpdateLog(file: paths.logFile)
        self.apiBase = apiBase
    }

    // MARK: - Check

    public func latestRelease(token: String?) async throws -> GitHubRelease {
        let url = apiBase.appendingPathComponent("repos/\(configuration.repository)/releases/latest")
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("\(configuration.appName)/\(configuration.currentVersion)", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200:
            return try GitHubRelease.decode(data)
        case 404:
            throw (token?.isEmpty ?? true) ? UpdaterError.needsToken : UpdaterError.noRelease
        case 401:
            throw UpdaterError.badToken
        case 403, 429:
            throw UpdaterError.rateLimited
        default:
            throw UpdaterError.http(status)
        }
    }

    // MARK: - Download and verify

    /// Downloads the release zip, checks it against GitHub's checksum, unpacks it and checks
    /// the app inside. Returns the verified app, staged in the Updates folder.
    public func prepare(
        release: GitHubRelease,
        token: String?,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        guard let asset = release.asset(for: configuration) else {
            throw UpdaterError.noAsset(configuration.assetName(for: release.version))
        }
        let fileManager = FileManager.default
        let folder = paths.updatesFolder.appendingPathComponent(release.version, isDirectory: true)
        try? fileManager.removeItem(at: folder)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let zip = folder.appendingPathComponent(asset.name)

        log.write("Downloading \(asset.name) (\(asset.size) bytes)")
        var request: URLRequest
        if let token, !token.isEmpty {
            // Private repositories: the API URL with a token. The redirect to storage drops the token.
            request = URLRequest(url: asset.apiURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        } else {
            request = URLRequest(url: asset.browserDownloadURL)
        }
        request.timeoutInterval = 60
        try await FileDownloader(destination: zip, progress: progress).download(request)

        if let expected = asset.sha256 {
            let actual = try Self.sha256(of: zip)
            guard actual == expected else {
                log.write("Checksum mismatch: expected \(expected), got \(actual)")
                throw UpdaterError.checksumMismatch
            }
            log.write("Checksum verified")
        } else {
            log.write("GitHub published no checksum for this asset; relying on HTTPS and the signature check")
        }

        let unpacked = folder.appendingPathComponent("unpacked", isDirectory: true)
        try fileManager.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let unzip = try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
        guard unzip.status == 0 else { throw UpdaterError.unzipFailed(unzip.output) }
        let contents = try fileManager.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw UpdaterError.unzipFailed("No app found in the zip.")
        }

        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any] ?? [:]
        let identifier = info["CFBundleIdentifier"] as? String ?? "unknown"
        guard identifier == configuration.bundleIdentifier else { throw UpdaterError.wrongApp(identifier) }
        let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
        guard VersionComparison.compare(version, release.version) == .orderedSame else {
            throw UpdaterError.versionMismatch(expected: release.version, found: version)
        }
        let signature = try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
        guard signature.status == 0 else { throw UpdaterError.signatureInvalid(signature.output) }

        try? fileManager.removeItem(at: zip)
        log.write("Version \(version) downloaded and verified")
        return app
    }

    // MARK: - Install

    /// Checks that the running app can be replaced in place.
    public func checkInstallable(currentApp: URL) throws {
        if currentApp.path.contains("/AppTranslocation/") {
            throw UpdaterError.notInstallable("macOS is running \(configuration.appName) from a temporary location. Move it to your Applications folder, open it from there, and try again.")
        }
        let parent = currentApp.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            throw UpdaterError.notInstallable("\(configuration.appName) can't write to \(parent). Move it to your Applications folder and try again.")
        }
    }

    /// Starts a small script that waits for this process to quit, swaps in the new app, keeps the
    /// previous version for recovery, and reopens the app if `relaunch` is true. Quit right after.
    public func startInstall(stagedApp: URL, currentApp: URL, relaunch: Bool) throws {
        try checkInstallable(currentApp: currentApp)
        let script = paths.updatesFolder.appendingPathComponent("install-update.sh")
        try FileManager.default.createDirectory(at: paths.updatesFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.previousVersion.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.installScript.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            stagedApp.path,
            currentApp.path,
            paths.previousVersion.path,
            relaunch ? "1" : "0",
            paths.logFile.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        log.write("Install started for \(stagedApp.lastPathComponent); relaunch: \(relaunch)")
    }

    static let installScript = """
    #!/bin/bash
    # Finishes installing an update after the app quits. Arguments:
    # PID NEW_APP CURRENT_APP PREVIOUS_COPY RELAUNCH(1/0) LOG
    PID="$1"; NEW="$2"; DEST="$3"; PREVIOUS="$4"; RELAUNCH="$5"; LOG="$6"
    exec >>"$LOG" 2>&1
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) installer: waiting for the app to quit"
    for i in $(seq 1 300); do kill -0 "$PID" 2>/dev/null || break; sleep 0.2; done
    rm -rf "$PREVIOUS"
    if ! mv "$DEST" "$PREVIOUS"; then
      echo "installer: couldn't move the current app aside; nothing changed"
      [ "$RELAUNCH" = "1" ] && /usr/bin/open "$DEST"
      exit 1
    fi
    if mv "$NEW" "$DEST" || /usr/bin/ditto "$NEW" "$DEST"; then
      echo "installer: installed; previous version kept at $PREVIOUS"
    else
      echo "installer: install failed; restoring the previous version"
      rm -rf "$DEST"
      mv "$PREVIOUS" "$DEST"
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
    [ "$RELAUNCH" = "1" ] && /usr/bin/open "$DEST"
    exit 0
    """

    // MARK: - Helpers

    public static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func run(_ tool: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: (finished.terminationStatus, output))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Downloads one file with progress, dropping the Authorization header on redirects.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var moveError: Error?

    init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    func download(_ request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
            session.downloadTask(with: request).resume()
            session.finishTasksAndInvalidate()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            moveError = UpdaterError.http(status)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            moveError = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        var redirected = request
        redirected.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(redirected)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let continuation = self.continuation
        self.continuation = nil
        if let error {
            continuation?.resume(throwing: error)
        } else if let moveError {
            continuation?.resume(throwing: moveError)
        } else {
            continuation?.resume()
        }
    }
}
