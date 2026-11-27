import SwiftUI

@main
struct WebsiteApp: App {
    @State private var model = AppModel()
    @State private var updates = UpdateController()

    var body: some Scene {
        WindowGroup("Website", id: "main") {
            ContentView()
                .environment(model)
                .environment(updates)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton()
                    .environment(updates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Site…") { model.isAddingSite = true }
                    .keyboardShortcut("n", modifiers: .command)
            }
        }

        Window("Add to Squarespace", id: "editor") {
            EditorWindowView()
                .environment(model)
        }
        .defaultSize(width: 1280, height: 860)

        Window("Software Update", id: "updates") {
            UpdateWindowView()
                .environment(updates)
        }
        .windowResizability(.contentSize)

        Settings {
            SettingsView()
                .environment(updates)
        }
    }
}
