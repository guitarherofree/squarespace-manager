import SiteKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            if let id = model.selectedSiteID, model.site(id) != nil {
                SiteDetailView(siteID: id)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Site Yet", systemImage: "globe")
                } description: {
                    Text("Add your Squarespace site to preview it and take snapshots.")
                } actions: {
                    Button("Add Site…") { model.isAddingSite = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $model.isAddingSite) {
            AddSiteSheet()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selectedSiteID) {
            Section("Sites") {
                ForEach(model.sites) { site in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(site.name)
                            .lineLimit(1)
                        Text(URL(string: site.url)?.host ?? site.url)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                    .tag(site.id as UUID?)
                    .contextMenu {
                        Button("Remove from List", role: .destructive) {
                            model.removeSite(site.id)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button {
                    model.isAddingSite = true
                } label: {
                    Label("Add Site", systemImage: "plus")
                }
                .help("Add a site")
            }
        }
    }
}

struct SiteDetailView: View {
    let siteID: UUID

    var body: some View {
        TabView {
            SiteOverviewView(siteID: siteID)
                .tabItem { Label("Overview", systemImage: "info.circle") }
            SitePreviewView(siteID: siteID)
                .tabItem { Label("Preview", systemImage: "macwindow") }
            SnapshotsView(siteID: siteID)
                .tabItem { Label("Snapshots", systemImage: "clock.arrow.circlepath") }
        }
        .padding(.top, 8)
    }
}
