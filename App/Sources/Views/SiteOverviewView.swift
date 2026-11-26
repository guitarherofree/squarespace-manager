import SiteKit
import SwiftUI

struct SiteOverviewView: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID

    var body: some View {
        if let site = model.site(siteID) {
            Form {
                Section("Site") {
                    LabeledContent("Title", value: site.info?.siteTitle ?? site.name)
                    LabeledContent("Address") {
                        if let url = site.homeURL {
                            Link(url.absoluteString, destination: url)
                        } else {
                            Text(site.url)
                        }
                    }
                    LabeledContent("Squarespace version") {
                        VersionBadge(info: site.info)
                    }
                    LabeledContent("Template ID", value: site.info?.templateID ?? "Not found")
                    if let detected = site.info?.detectedAt {
                        LabeledContent("Last checked") {
                            Text(detected, format: .dateTime.month().day().hour().minute())
                        }
                    }
                    HStack {
                        Spacer()
                        if model.refreshing.contains(siteID) {
                            ProgressView().controlSize(.small)
                        }
                        Button("Check Again") {
                            Task { await model.refreshDetection(for: siteID) }
                        }
                        .disabled(model.refreshing.contains(siteID))
                    }
                }

                Section {
                    Picker("Squarespace plan", selection: Binding(
                        get: { model.site(siteID)?.plan ?? .unknown },
                        set: { model.setPlan($0, for: siteID) }
                    )) {
                        ForEach(SquarespacePlan.allCases) { plan in
                            Text(plan.displayName).tag(plan)
                        }
                    }
                    LabeledContent("Publishing") {
                        Text(site.plan == .unknown ? "Choose a plan" : site.plan.publishingRoute.title)
                    }
                    Text(site.plan == .unknown
                         ? "Your plan decides how style changes will reach the live site. You'll find it in Squarespace under Settings › Billing."
                         : site.plan.publishingRoute.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Plan and publishing")
                }

                Section("Snapshots") {
                    SnapshotSummary(siteID: siteID)
                }

                Section("Coming in later updates") {
                    Text("Selecting and editing elements, the style layer, publishing, hand-off editing for content, the AI assistant and the site health dashboard.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
    }
}

struct VersionBadge: View {
    let info: SiteInfo?

    var body: some View {
        if let info, info.version != .unknown {
            HStack(spacing: 6) {
                Text(info.version.displayName)
                    .fontWeight(.semibold)
                Text(info.versionConfidence == .confirmed ? "from Squarespace's page data" : "best guess from the page markup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Couldn't tell")
                .foregroundStyle(.secondary)
        }
    }
}

struct SnapshotSummary: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID

    var body: some View {
        let list = model.manifests[siteID] ?? []
        if let progress = model.snapshotProgress[siteID] {
            SnapshotProgressRow(siteID: siteID, progress: progress)
        } else if let latest = list.first {
            LabeledContent("Latest") {
                Text(latest.createdAt, format: .dateTime.month().day().year().hour().minute())
            }
            LabeledContent("Pages saved", value: "\(latest.pages.count)")
            if let diff = model.diff(for: latest.id, site: siteID) {
                LabeledContent("Since the previous snapshot") {
                    Text(diffSummary(diff))
                }
            }
            HStack {
                Spacer()
                Button("Take Snapshot") { model.startSnapshot(for: siteID) }
            }
        } else {
            Text("A snapshot saves every page's content, markup and the site's CSS on this Mac, so later changes made in Squarespace can be spotted.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Take First Snapshot") { model.startSnapshot(for: siteID) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func diffSummary(_ diff: SnapshotDiff) -> String {
        if diff.isBaseline { return "First snapshot" }
        let changed = diff.changedEntries.filter { $0.kind != .failed }.count
        var parts: [String] = []
        parts.append(changed == 0 ? "No page changes" : "\(changed) page\(changed == 1 ? "" : "s") changed")
        if diff.cssChanged { parts.append("CSS changed") }
        return parts.joined(separator: ", ")
    }
}

struct SnapshotProgressRow: View {
    @Environment(AppModel.self) private var model
    let siteID: UUID
    let progress: SnapshotProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(progress.total > 0 ? "Page \(min(progress.completed + 1, progress.total)) of \(progress.total): \(progress.message)" : progress.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Cancel") { model.cancelSnapshot(for: siteID) }
                    .controlSize(.small)
            }
        }
    }
}
