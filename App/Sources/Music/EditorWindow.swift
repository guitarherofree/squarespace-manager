import AppKit
import SiteKit
import SwiftUI
import WebKit

/// Squarespace's own editor beside a checklist of prepared files. You do the editing; the app
/// lays out what goes where, lets you drag each file straight onto the page, and checks the result.
struct EditorWindowView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let id = app.editorSiteID, let music = app.music(for: id), let batch = music.preparedBatch {
            HSplitView {
                ChecklistView(music: music, batch: batch)
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 440)
                SquarespaceEditorView(url: music.editorURL)
                    .frame(minWidth: 640, minHeight: 600)
            }
        } else {
            ContentUnavailableView(
                "Nothing to Add Yet",
                systemImage: "music.note.list",
                description: Text("In the Music tab, select the pieces to add, then click Add to Site.")
            )
            .frame(minWidth: 500, minHeight: 300)
        }
    }
}

private struct ChecklistView: View {
    let music: MusicModel
    let batch: UploadBatch
    @State private var done: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add \(batch.items.count) piece\(batch.items.count == 1 ? "" : "s") to the Music page")
                        .font(.headline)

                    step(1, "Sign in on the right, open **Pages › \(pageName)** and click **Edit**.")
                    step(2, "Drag each file below onto the page where it says. Squarespace makes an audio player for it. Set the player's design to **Minimal**, turn downloads off, and copy the title and second line from here.")

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(batch.items) { item in
                            ItemRow(item: item, isDone: Binding(
                                get: { done.contains(item.id) || item.isOnSite },
                                set: { isOn in
                                    if isOn { done.insert(item.id) } else { done.remove(item.id) }
                                }
                            ))
                        }
                    }

                    step(3, "Click **Save** in Squarespace, then **Check the Site** below.")
                }
                .padding(16)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                let live = batch.items.filter(\.isOnSite).count
                if live > 0 {
                    Label("\(live) of \(batch.items.count) now on the site", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
                HStack {
                    Button {
                        Task { await music.readSite() }
                    } label: {
                        if music.isReadingSite {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Check the Site")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(music.isReadingSite)
                    Spacer()
                    Menu("More") {
                        Button("Show Files in Finder") { music.showBatchInFinder() }
                        Button("Open Squarespace in Your Browser") { NSWorkspace.shared.open(music.editorURL) }
                        Button("Open the Live Music Page") { NSWorkspace.shared.open(music.pageURL) }
                    }
                    .fixedSize()
                }
                Text("If signing in here doesn't work (for example with Google), use Open Squarespace in Your Browser and drag the files from Finder.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private var pageName: String {
        let trimmed = music.pagePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "Home" : trimmed.capitalized
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number)")
                .font(.callout.weight(.semibold))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))
            Text(.init(text))
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ItemRow: View {
    let item: UploadItem
    @Binding var isDone: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: $isDone)
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                    Text(item.title)
                        .fontWeight(.semibold)
                        .strikethrough(isDone)
                    Spacer()
                    copyButton(item.title, help: "Copy the title")
                }
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    HStack(spacing: 6) {
                        Text("Second line: \(subtitle)")
                            .font(.caption)
                        Spacer()
                        copyButton(subtitle, help: "Copy the second line")
                    }
                }
                Text(item.placement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(item.file.lastPathComponent + (item.durationSeconds.map { " · " + DurationText.format($0) } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if item.isOnSite {
                    Label("On the site", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .contentShape(Rectangle())
        .onDrag {
            NSItemProvider(contentsOf: item.file) ?? NSItemProvider()
        }
        .help("Drag onto the page in Squarespace to add this recording")
    }

    private func copyButton(_ text: String, help: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

/// A browser pane for Squarespace's editor. It keeps its sign-in between launches and handles
/// the file pickers, dialogs and pop-up windows the editor uses. The app never clicks or types in it.
struct SquarespaceEditorView: NSViewRepresentable {
    let url: URL

    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.customUserAgent = Self.safariUserAgent
        view.allowsBackForwardNavigationGestures = true
        view.uiDelegate = context.coordinator
        view.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.loadedURL != url {
            view.load(URLRequest(url: url))
            context.coordinator.loadedURL = url
        }
    }

    final class Coordinator: NSObject, WKUIDelegate {
        var loadedURL: URL?

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Open pop-ups in the same pane.
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        @objc(webView:runOpenPanelWithParameters:initiatedByFrame:completionHandler:)
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        @objc(webView:runJavaScriptAlertPanelWithMessage:initiatedByFrame:completionHandler:)
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.runModal()
            completionHandler()
        }

        @objc(webView:runJavaScriptConfirmPanelWithMessage:initiatedByFrame:completionHandler:)
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            completionHandler(alert.runModal() == .alertFirstButtonReturn)
        }
    }
}
