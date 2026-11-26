import SwiftUI

@main
struct SquarespaceManagerApp: App {
    @State private var model = AppModel()
    @State private var updater = AppUpdater()

    var body: some Scene {
        WindowGroup("Squarespace Manager") {
            ContentView()
                .environment(model)
                .environment(updater)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
                    .environment(updater)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Site…") { model.isAddingSite = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(updater)
        }
    }
}
