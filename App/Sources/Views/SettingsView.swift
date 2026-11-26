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
        .frame(width: 500, height: 420)
    }
}

struct AboutSettingsView: View {
    @Environment(UpdateController.self) private var updates

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Website")
                .font(.title3.weight(.semibold))
            Text("Version \(AppInfo.versionString)")
                .foregroundStyle(.secondary)
            Text("Previews, tracks and edits freemanedwards.com. Not affiliated with Squarespace.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
            if let url = updates.repositoryURL {
                Link("Source and releases on GitHub", destination: url)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
