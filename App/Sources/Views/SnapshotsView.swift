import AppKit
import SiteKit
import SwiftUI

struct SnapshotsView: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID
    @State private var selection: String?
    @State private var showUnchanged = false

    var body: some View {
        let list = model.manifests[siteID] ?? []
        VStack(spacing: 0) {
            HStack {
                if let progress = model.snapshotProgress[siteID] {
                    SnapshotProgressRow(siteID: siteID, progress: progress)
                        .frame(maxWidth: 420)
                } else {
                    Button("Take Snapshot") { model.startSnapshot(for: siteID) }
                }
                Spacer()
                Toggle("Show unchanged pages", isOn: $showUnchanged)
                    .toggleStyle(.checkbox)
                Button {
                    let folder = model.snapshotsFolder(for: siteID)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if list.isEmpty {
                ContentUnavailableView(
                    "No Snapshots",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Take a snapshot to save a copy of the site and track changes made outside the app.")
                )
            } else {
                HSplitView {
                    List(list, selection: $selection) { manifest in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(manifest.createdAt, format: .dateTime.month().day().year().hour().minute())
                            Text("\(manifest.pages.count) pages" + (manifest.failedPageCount > 0 ? ", \(manifest.failedPageCount) unreadable" : ""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(manifest.id as String?)
                    }
                    .frame(minWidth: 220, idealWidth: 250, maxWidth: 340)

                    SnapshotDiffView(
                        siteID: siteID,
                        snapshotID: selection ?? list.first?.id,
                        showUnchanged: showUnchanged
                    )
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct SnapshotDiffView: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID
    let snapshotID: String?
    let showUnchanged: Bool

    var body: some View {
        if let snapshotID, let diff = model.diff(for: snapshotID, site: siteID) {
            let entries = sorted(diff.entries.filter { showUnchanged || $0.kind != .unchanged })
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline(diff))
                        .font(.headline)
                    Text(diff.isBaseline
                         ? "This is the first snapshot, so there's nothing to compare it with yet."
                         : "Compared with the snapshot before it. Content changes come from the page data; markup changes can include small template updates by Squarespace.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)

                Divider()

                if entries.isEmpty {
                    ContentUnavailableView("No Changes", systemImage: "checkmark.circle", description: Text("Every page matches the previous snapshot."))
                } else {
                    List(entries) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: symbol(for: entry.kind))
                                .foregroundStyle(color(for: entry.kind))
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.title ?? path(of: entry.url))
                                    .lineLimit(1)
                                Text(path(of: entry.url))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(entry.kind.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView("Select a Snapshot", systemImage: "clock")
        }
    }

    private func headline(_ diff: SnapshotDiff) -> String {
        if diff.isBaseline { return "\(diff.entries.count) pages saved" }
        let changed = diff.changedEntries.filter { $0.kind != .failed }.count
        let pages = changed == 0 ? "No page changes" : "\(changed) page\(changed == 1 ? "" : "s") changed"
        return pages + (diff.cssChanged ? " · site CSS changed" : " · site CSS unchanged")
    }

    private func sorted(_ entries: [SnapshotDiff.Entry]) -> [SnapshotDiff.Entry] {
        let order: [SnapshotDiff.Kind] = [.contentChanged, .added, .removed, .markupChanged, .failed, .unchanged]
        return entries.sorted { a, b in
            let ia = order.firstIndex(of: a.kind) ?? order.count
            let ib = order.firstIndex(of: b.kind) ?? order.count
            if ia != ib { return ia < ib }
            return a.url < b.url
        }
    }

    private func path(of url: String) -> String {
        guard let parsed = URL(string: url) else { return url }
        return parsed.path.isEmpty ? "/" : parsed.path
    }

    private func symbol(for kind: SnapshotDiff.Kind) -> String {
        switch kind {
        case .added: return "plus.circle.fill"
        case .removed: return "minus.circle.fill"
        case .contentChanged: return "pencil.circle.fill"
        case .markupChanged: return "chevron.left.forwardslash.chevron.right"
        case .unchanged: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for kind: SnapshotDiff.Kind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .contentChanged: return .orange
        case .markupChanged: return .secondary
        case .unchanged: return .secondary
        case .failed: return .yellow
        }
    }
}
