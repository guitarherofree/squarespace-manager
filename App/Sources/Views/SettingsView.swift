import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            UpdateSettingsView()
                .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 300)
    }
}

struct UpdateSettingsView: View {
    @Environment(AppUpdater.self) private var updater

    var body: some View {
        Form {
            LabeledContent("Installed version", value: AppInfo.versionString)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecks },
                set: { updater.setAutomaticallyChecks($0) }
            ))
            Toggle("Download updates in the background", isOn: Binding(
                get: { updater.automaticallyDownloads },
                set: { updater.setAutomaticallyDownloads($0) }
            ))
            .disabled(!updater.automaticallyChecks)
            LabeledContent("Last checked") {
                if let date = updater.lastCheckDate {
                    Text(date, format: .dateTime.month().day().hour().minute())
                } else {
                    Text("Not yet")
                }
            }
            HStack {
                Text("When an update is found you'll see its version and release notes, and can install it now or later.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                CheckForUpdatesButton()
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Squarespace Manager")
                .font(.title3.weight(.semibold))
            Text("Version \(AppInfo.versionString)")
                .foregroundStyle(.secondary)
            Text("A personal tool for previewing, tracking and editing a Squarespace site. Not affiliated with Squarespace.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            Link("Source and releases on GitHub", destination: URL(string: "https://github.com/guitarherofree/squarespace-manager")!)
                .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
