import AppKit
import GitHubReleaseUpdater
import SwiftUI

/// "Check for Updates…" in the app menu: opens the update window and checks.
struct CheckForUpdatesButton: View {
    @Environment(UpdateController.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check for Updates…") {
            openWindow(id: "updates")
            Task { await updates.check(userInitiated: true) }
        }
    }
}

/// A thin bar at the top of the main window when an update needs attention.
struct UpdateBanner: View {
    @Environment(UpdateController.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        switch updates.state {
        case .available:
            bar(icon: "arrow.down.circle.fill", text: "Website \(updates.latest?.version ?? "") is available.") {
                Button("Details…") { openWindow(id: "updates") }
                Button("Download and Install") { Task { await updates.download() } }
            }
        case .downloading(let fraction):
            bar(icon: "arrow.down.circle", text: "Downloading Website \(updates.latest?.version ?? "")…") {
                ProgressView(value: fraction).frame(width: 120)
            }
        case .ready:
            bar(icon: "checkmark.circle.fill", text: "Website \(updates.latest?.version ?? "") is ready. It installs when you quit, or now.") {
                Button("What's New") { openWindow(id: "updates") }
                Button("Restart Now") { updates.restartAndInstall() }
                    .buttonStyle(.borderedProminent)
            }
        default:
            EmptyView()
        }
    }

    private func bar<Buttons: View>(icon: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
            Text(text)
                .lineLimit(1)
            Spacer()
            buttons()
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// The Software Update window: versions, release notes, progress and actions.
struct UpdateWindowView: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.headline)
                    Text("Installed: \(updates.currentVersion)" + (updates.latest.map { " · Latest: \($0.version)" } ?? ""))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let notes = updates.latest?.body, !notes.isEmpty,
               updates.state != .upToDate, updates.state != .checking {
                ScrollView {
                    Text(Self.attributed(notes))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(10)
                }
                .frame(height: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))
            }

            if case .downloading(let fraction) = updates.state {
                ProgressView(value: fraction)
            }
            if case .failed(let message) = updates.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Show Log") { updates.showLog() }
                Spacer()
                actions
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var headline: String {
        switch updates.state {
        case .idle: return "Software Update"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Website is up to date"
        case .available: return "Website \(updates.latest?.version ?? "") is available"
        case .downloading: return "Downloading Website \(updates.latest?.version ?? "")…"
        case .ready: return "Website \(updates.latest?.version ?? "") is ready to install"
        case .installing: return "Installing…"
        case .failed: return "The update didn't finish"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch updates.state {
        case .available:
            Button("Skip This Version") { updates.skipLatest() }
            Button("Download and Install") { Task { await updates.download() } }
                .keyboardShortcut(.defaultAction)
        case .ready:
            Text("Installs when you quit")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Restart Now") { updates.restartAndInstall() }
                .keyboardShortcut(.defaultAction)
        case .failed:
            Button("Try Again") { Task { await updates.check(userInitiated: true) } }
                .keyboardShortcut(.defaultAction)
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .idle, .upToDate:
            Button("Check Again") { Task { await updates.check(userInitiated: true) } }
                .keyboardShortcut(.defaultAction)
        }
    }

    static func attributed(_ markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
    }
}

/// Settings › Updates.
struct UpdateSettingsView: View {
    @Environment(UpdateController.self) private var updates
    @State private var tokenText = ""

    var body: some View {
        Form {
            LabeledContent("Installed version", value: AppInfo.versionString)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updates.automaticallyChecks },
                set: { updates.setAutomaticallyChecks($0) }
            ))
            Toggle("Download updates in the background", isOn: Binding(
                get: { updates.automaticallyDownloads },
                set: { updates.setAutomaticallyDownloads($0) }
            ))
            LabeledContent("Last checked") {
                if let date = updates.lastChecked {
                    Text(date, format: .dateTime.month().day().hour().minute())
                } else {
                    Text("Not yet")
                }
            }
            HStack {
                Button("Show Log") { updates.showLog() }
                Spacer()
                CheckForUpdatesButton()
            }

            Section {
                if updates.hasToken {
                    LabeledContent("GitHub token", value: "Saved in your Keychain")
                    Button("Remove Token", role: .destructive) { updates.removeToken() }
                } else {
                    SecureField("GitHub token", text: $tokenText, prompt: Text("github_pat_…"))
                    Button("Save Token") {
                        updates.saveToken(tokenText)
                        tokenText = ""
                    }
                    .disabled(tokenText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Private repository access")
            } footer: {
                Text("Only needed if the repository becomes private. Use a fine-grained token with read-only Contents access to this repository.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
