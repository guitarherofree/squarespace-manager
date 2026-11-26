import AppKit
import Foundation
import GitHubReleaseUpdater
import Observation

/// Runs the standard GitHub Releases updater: checks shortly after launch and then daily,
/// downloads in the background, and installs on "Restart Now" or when the app quits.
@MainActor
@Observable
final class UpdateController {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available
        case downloading(Double)
        case ready
        case installing
        case failed(String)
    }

    private enum Keys {
        static let autoCheck = "updates.automaticallyCheck"
        static let autoDownload = "updates.automaticallyDownload"
        static let lastChecked = "updates.lastChecked"
        static let skipped = "updates.skippedVersion"
    }

    private(set) var state: State = .idle
    private(set) var latest: GitHubRelease?
    private(set) var lastChecked: Date?
    private(set) var automaticallyChecks: Bool
    private(set) var automaticallyDownloads: Bool
    private(set) var hasToken: Bool

    let currentVersion = AppInfo.version

    private let updater: GitHubUpdater?
    private let tokens: TokenStore
    @ObservationIgnored private var stagedApp: URL?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?

    init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [Keys.autoCheck: true, Keys.autoDownload: true])
        automaticallyChecks = defaults.bool(forKey: Keys.autoCheck)
        automaticallyDownloads = defaults.bool(forKey: Keys.autoDownload)
        lastChecked = defaults.object(forKey: Keys.lastChecked) as? Date
        let tokenStore = TokenStore(appName: AppInfo.name)
        tokens = tokenStore
        hasToken = tokenStore.read() != nil

        let repository = Bundle.main.object(forInfoDictionaryKey: "GitHubRepository") as? String ?? ""
        if repository.isEmpty {
            updater = nil
        } else {
            updater = GitHubUpdater(configuration: UpdaterConfiguration(
                repository: repository,
                appName: AppInfo.name,
                currentVersion: AppInfo.version,
                bundleIdentifier: Bundle.main.bundleIdentifier ?? ""
            ))
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.installOnQuitIfReady()
            }
        }
        scheduleAutomaticChecks()
    }

    var repositoryURL: URL? {
        guard let repository = updater?.configuration.repository else { return nil }
        return URL(string: "https://github.com/\(repository)")
    }

    var logFile: URL? { updater?.paths.logFile }

    // MARK: - Settings

    func setAutomaticallyChecks(_ value: Bool) {
        automaticallyChecks = value
        UserDefaults.standard.set(value, forKey: Keys.autoCheck)
    }

    func setAutomaticallyDownloads(_ value: Bool) {
        automaticallyDownloads = value
        UserDefaults.standard.set(value, forKey: Keys.autoDownload)
    }

    func saveToken(_ token: String) {
        tokens.save(token)
        hasToken = tokens.read() != nil
        Task { await check(userInitiated: true) }
    }

    func removeToken() {
        tokens.delete()
        hasToken = false
    }

    // MARK: - Checking

    private func scheduleAutomaticChecks() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.automaticCheck(onLaunch: true)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.automaticCheck(onLaunch: false)
            }
        }
    }

    private func automaticCheck(onLaunch: Bool) {
        guard automaticallyChecks, updater != nil else { return }
        if !onLaunch, let lastChecked, Date().timeIntervalSince(lastChecked) < 24 * 3600 { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard let updater else {
            state = .failed("This build doesn't name a GitHub repository for updates.")
            return
        }
        switch state {
        case .checking, .downloading, .ready, .installing:
            return
        default:
            break
        }
        state = .checking
        do {
            let release = try await updater.latestRelease(token: tokens.read())
            latest = release
            let now = Date()
            lastChecked = now
            UserDefaults.standard.set(now, forKey: Keys.lastChecked)
            let skipped = UserDefaults.standard.string(forKey: Keys.skipped)
            guard VersionComparison.isNewer(release.version, than: currentVersion),
                  userInitiated || skipped != release.version else {
                state = .upToDate
                return
            }
            updater.log.write("Version \(release.version) is available (installed: \(currentVersion))")
            state = .available
            if automaticallyDownloads {
                await download()
            }
        } catch {
            updater.log.write("Check failed: \(error.localizedDescription)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    // MARK: - Downloading and installing

    func download() async {
        guard let updater, let release = latest else { return }
        state = .downloading(0)
        do {
            let app = try await updater.prepare(release: release, token: tokens.read()) { [weak self] fraction in
                Task { @MainActor in
                    guard let self, case .downloading = self.state else { return }
                    self.state = .downloading(fraction)
                }
            }
            stagedApp = app
            state = .ready
        } catch {
            updater.log.write("Download failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    func skipLatest() {
        guard let version = latest?.version else { return }
        UserDefaults.standard.set(version, forKey: Keys.skipped)
        state = .upToDate
    }

    func restartAndInstall() {
        guard let updater, let stagedApp else { return }
        do {
            try updater.startInstall(stagedApp: stagedApp, currentApp: Bundle.main.bundleURL, relaunch: true)
            state = .installing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.terminate(nil)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func installOnQuitIfReady() {
        guard state == .ready, let updater, let stagedApp else { return }
        try? updater.startInstall(stagedApp: stagedApp, currentApp: Bundle.main.bundleURL, relaunch: false)
    }

    func showLog() {
        guard let logFile else { return }
        if FileManager.default.fileExists(atPath: logFile.path) {
            NSWorkspace.shared.open(logFile)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([logFile.deletingLastPathComponent()])
        }
    }
}
