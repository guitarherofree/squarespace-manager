import SwiftUI
import WebKit

enum PreviewDevice: String, CaseIterable, Identifiable {
    case desktop, tablet, mobile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: return "Desktop"
        case .tablet: return "Tablet"
        case .mobile: return "Mobile"
        }
    }

    var symbol: String {
        switch self {
        case .desktop: return "desktopcomputer"
        case .tablet: return "ipad"
        case .mobile: return "iphone"
        }
    }

    /// Viewport width in points; nil fills the window.
    var width: CGFloat? {
        switch self {
        case .desktop: return nil
        case .tablet: return 820
        case .mobile: return 390
        }
    }
}

struct SitePreviewView: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID
    @State private var device: PreviewDevice = .desktop
    @State private var reloadToken = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Device", selection: $device) {
                    ForEach(PreviewDevice.allCases) { device in
                        Label(device.title, systemImage: device.symbol).tag(device)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 300)

                Button {
                    reloadToken += 1
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .help("Reload the live site")

                Spacer()

                Text("Live site, read-only. Width preview only; touch behavior isn't simulated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let url = model.site(siteID)?.homeURL {
                    Link(destination: url) {
                        Label("Open in Browser", systemImage: "safari")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if let url = model.site(siteID)?.homeURL {
                GeometryReader { geometry in
                    let width = min(device.width ?? geometry.size.width, geometry.size.width)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        WebView(url: url, reloadToken: reloadToken)
                            .frame(width: width)
                            .overlay(alignment: .leading) {
                                if device.width != nil { Divider() }
                            }
                            .overlay(alignment: .trailing) {
                                if device.width != nil { Divider() }
                            }
                        Spacer(minLength: 0)
                    }
                    .background(Color(nsColor: .windowBackgroundColor))
                }
            }
        }
    }
}

/// A WKWebView that shows the site as a logged-out visitor sees it.
struct WebView: NSViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.allowsBackForwardNavigationGestures = true
        context.coordinator.load(url, token: reloadToken, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, token: reloadToken, in: view)
    }

    final class Coordinator {
        private var loadedURL: URL?
        private var loadedToken: Int?

        func load(_ url: URL, token: Int, in view: WKWebView) {
            if loadedURL == url && loadedToken == token { return }
            if loadedURL == url {
                view.reload()
            } else {
                view.load(URLRequest(url: url))
            }
            loadedURL = url
            loadedToken = token
        }
    }
}
