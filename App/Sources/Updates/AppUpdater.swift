import Foundation
import Observation
import Sparkle
import SwiftUI

/// Wraps Sparkle's standard updater. Sparkle shows its own windows for release notes,
/// download progress and "Install now or later".
@Observable
final class AppUpdater {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private(set) var canCheckForUpdates = false
    private(set) var automaticallyChecks: Bool
    private(set) var automaticallyDownloads: Bool

    init() {
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        self.automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        self.automaticallyDownloads = controller.updater.automaticallyDownloadsUpdates
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] updater, _ in
            let value = updater.canCheckForUpdates
            DispatchQueue.main.async {
                self?.canCheckForUpdates = value
            }
        }
    }

    var lastCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecks(_ value: Bool) {
        controller.updater.automaticallyChecksForUpdates = value
        automaticallyChecks = value
    }

    func setAutomaticallyDownloads(_ value: Bool) {
        controller.updater.automaticallyDownloadsUpdates = value
        automaticallyDownloads = value
    }
}

struct CheckForUpdatesButton: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
