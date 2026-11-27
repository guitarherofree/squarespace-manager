import SiteKit
import SwiftUI

struct MusicView: View {
    @Environment(AppModel.self) private var app
    let siteID: UUID

    var body: some View {
        if let music = app.music(for: siteID) {
            MusicContentView(music: music, siteID: siteID)
        } else {
            ContentUnavailableView("Music Unavailable", systemImage: "music.note.list",
                                   description: Text("This site has no address saved."))
        }
    }
}

private enum MusicFilter: String, CaseIterable, Identifiable {
    case notOnSite, onSite, missingFromFolder

    var id: String { rawValue }
}

private struct YearGroup<Item: Identifiable>: Identifiable {
    var year: Int?
    var items: [Item]
    var id: String { year.map(String.init) ?? "unknown" }
    var title: String { year.map(String.init) ?? "Year unknown" }
}

struct MusicContentView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow
    let music: MusicModel
    let siteID: UUID
    @State private var filter: MusicFilter = .notOnSite
    @State private var pagePathText = ""

    var body: some View {
        let comparison = music.comparison
        VStack(spacing: 0) {
            header
            Divider()
            if music.folder == nil {
                ContentUnavailableView {
                    Label("Choose Your Recordings Folder", systemImage: "folder")
                } description: {
                    Text("Website compares the folder with your Music page and shows which pieces aren't on the site yet. It only reads the folder.")
                } actions: {
                    Button("Choose Folder…") { music.chooseFolder() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                summary(comparison)
                Picker("Show", selection: $filter) {
                    Text("Not on Site (\(comparison.notOnSite.count))").tag(MusicFilter.notOnSite)
                    Text("On Site (\(comparison.onSite.count))").tag(MusicFilter.onSite)
                    Text("Missing From Folder (\(comparison.siteOnly.count))").tag(MusicFilter.missingFromFolder)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

                switch filter {
                case .notOnSite:
                    notOnSiteList(comparison)
                    Divider()
                    footer(comparison)
                case .onSite:
                    onSiteList(comparison)
                case .missingFromFolder:
                    missingList(comparison)
                }
            }
        }
        .task {
            pagePathText = music.pagePath
            if music.catalog == nil { await music.readSite() }
            if music.library.isEmpty, music.folder != nil { await music.scanFolder() }
        }
        .alert("Music", isPresented: Binding(
            get: { music.errorMessage != nil },
            set: { if !$0 { music.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(music.errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(music.folder?.path(percentEncoded: false) ?? "No folder chosen")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(music.folder == nil ? .secondary : .primary)
                if music.isScanning { ProgressView().controlSize(.small) }
                Spacer()
                Button(music.folder == nil ? "Choose Folder…" : "Change…") { music.chooseFolder() }
                if music.folder != nil {
                    Button {
                        Task { await music.scanFolder() }
                    } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                    .help("Look for new recordings in the folder")
                }
            }
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                Text("Music page")
                TextField("Page", text: $pagePathText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)
                    .onSubmit {
                        music.setPagePath(pagePathText)
                        pagePathText = music.pagePath
                        Task { await music.readSite() }
                    }
                if music.isReadingSite {
                    ProgressView().controlSize(.small)
                    Text("Reading the page…").font(.caption).foregroundStyle(.secondary)
                } else if let read = music.catalogReadAt {
                    Text("\(music.catalog?.entries.count ?? 0) pieces, read \(read.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await music.readSite() }
                } label: {
                    Label("Read Site", systemImage: "arrow.down.doc")
                }
                .disabled(music.isReadingSite)
            }
            if let note = music.catalogNote {
                Label(note, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func summary(_ comparison: MusicComparison) -> some View {
        let missing = comparison.notOnSite.count
        let text: String
        if music.catalog == nil {
            text = "Read the site to compare it with your folder."
        } else if missing == 0 {
            text = "Every recording in the folder is on the site."
        } else {
            text = "\(missing) recording\(missing == 1 ? "" : "s") in the folder \(missing == 1 ? "isn't" : "aren't") on the site yet."
        }
        return HStack {
            Text(text).font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Lists

    private func groups<Item: Identifiable>(_ items: [Item], year: (Item) -> Int?) -> [YearGroup<Item>] {
        var order: [Int?] = []
        var byYear: [Int: [Item]] = [:]
        var unknown: [Item] = []
        for item in items {
            if let value = year(item) {
                if byYear[value] == nil { order.append(value) }
                byYear[value, default: []].append(item)
            } else {
                unknown.append(item)
            }
        }
        var result = order.compactMap { $0 }.map { YearGroup(year: $0, items: byYear[$0] ?? []) }
        if !unknown.isEmpty { result.append(YearGroup(year: nil, items: unknown)) }
        return result
    }

    private func notOnSiteList(_ comparison: MusicComparison) -> some View {
        let catalog = music.catalog ?? MusicCatalog(entries: [])
        return List {
            if comparison.notOnSite.isEmpty {
                Text(music.catalog == nil ? "Read the site first." : "Nothing to add.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups(comparison.notOnSite, year: \.year)) { group in
                Section(group.title) {
                    ForEach(group.items) { piece in
                        PieceRow(music: music, piece: piece,
                                 placement: Placement.hint(title: piece.title, year: piece.year, catalog: catalog))
                    }
                }
            }
        }
    }

    private func onSiteList(_ comparison: MusicComparison) -> some View {
        List {
            ForEach(groups(comparison.onSite, year: \.entry.year)) { group in
                Section(group.title) {
                    ForEach(group.items) { match in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(match.entry.title)
                                if let subtitle = match.entry.subtitle {
                                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(DurationText.format(match.entry.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            if let local = match.local {
                                Label(local.fileExtension.uppercased(), systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .help(local.url.path(percentEncoded: false))
                            } else {
                                Label("Not in folder", systemImage: "questionmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func missingList(_ comparison: MusicComparison) -> some View {
        List {
            if comparison.siteOnly.isEmpty {
                Text("Every piece on the site has a recording in the folder.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups(comparison.siteOnly, year: \.year)) { group in
                Section(group.title) {
                    ForEach(group.items) { entry in
                        HStack {
                            Text(entry.title)
                            Spacer()
                            Text(DurationText.format(entry.durationSeconds))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private func footer(_ comparison: MusicComparison) -> some View {
        let available = comparison.notOnSite
        let selectedCount = available.filter { music.selection.contains($0.id) }.count
        return HStack(spacing: 10) {
            Button("Select All") { music.selection = Set(available.map(\.id)) }
                .disabled(available.isEmpty)
            Button("Select None") { music.selection = [] }
                .disabled(selectedCount == 0)
            Spacer()
            if music.isPreparing {
                ProgressView().controlSize(.small)
                Text("Preparing files…").font(.caption).foregroundStyle(.secondary)
            }
            if music.preparedBatch != nil {
                Button("Open Checklist") {
                    app.editorSiteID = siteID
                    openWindow(id: "editor")
                }
            }
            Button("Add \(selectedCount) to Site…") {
                Task {
                    if await music.prepareSelected() {
                        app.editorSiteID = siteID
                        openWindow(id: "editor")
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedCount == 0 || music.isPreparing || music.catalog == nil)
        }
        .padding(12)
    }
}

private struct PieceRow: View {
    let music: MusicModel
    let piece: LocalPiece
    let placement: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: Binding(
                get: { music.selection.contains(piece.id) },
                set: { isOn in
                    if isOn { music.selection.insert(piece.id) } else { music.selection.remove(piece.id) }
                }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(piece.title).fontWeight(.medium)
                    if piece.yearSource == .fileDate {
                        Text("year from file date")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                TextField("Second line, e.g. For violin, or a commission", text: Binding(
                    get: { music.subtitle(for: piece) },
                    set: { music.setSubtitle($0, for: piece) }
                ))
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.secondary)
                Text(placement)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(DurationText.format(music.durations[piece.id]))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(UploadPlan.plan(for: piece) == .copy
                     ? piece.fileExtension.uppercased()
                     : "\(piece.fileExtension.uppercased()) → M4A")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 3)
    }
}
