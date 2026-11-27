import AppKit
import Foundation
import Observation
import SiteKit

/// A file prepared for upload, with where it goes on the page.
struct UploadItem: Identifiable, Equatable {
    var id: String { file.path }
    var title: String
    var year: Int?
    var subtitle: String?
    var file: URL
    var placement: String
    var durationSeconds: Int?
    var isOnSite = false
}

struct UploadBatch: Equatable {
    var folder: URL
    var items: [UploadItem]
    var createdAt: Date
}

/// The Music tab for one site: the recordings folder, the site's music page, and adding pieces.
@MainActor
@Observable
final class MusicModel {
    let siteID: UUID
    let siteURL: URL
    private(set) var pagePath: String
    private(set) var folder: URL?
    private(set) var subtitles: [String: String]

    private(set) var catalog: MusicCatalog?
    private(set) var catalogNote: String?
    private(set) var catalogReadAt: Date?
    private(set) var library: [LocalPiece] = []
    private(set) var durations: [String: Int] = [:]
    private(set) var isReadingSite = false
    private(set) var isScanning = false
    private(set) var isPreparing = false
    private(set) var preparedBatch: UploadBatch?
    var errorMessage: String?
    var selection: Set<String> = []

    @ObservationIgnored var persist: ((URL?, String, [String: String]) -> Void)?
    @ObservationIgnored private let uploadsRoot: URL
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    init(siteID: UUID, siteURL: URL, folder: URL?, pagePath: String, subtitles: [String: String], uploadsRoot: URL) {
        self.siteID = siteID
        self.siteURL = siteURL
        self.folder = folder
        self.pagePath = pagePath
        self.subtitles = subtitles
        self.uploadsRoot = uploadsRoot
    }

    var comparison: MusicComparison {
        MusicComparison(library: library, catalog: catalog)
    }

    var pageURL: URL {
        let path = pagePath.hasPrefix("/") ? String(pagePath.dropFirst()) : pagePath
        return URL(string: path, relativeTo: siteURL)?.absoluteURL ?? siteURL
    }

    /// Squarespace's editor for the site; signing in happens there.
    var editorURL: URL {
        URL(string: "config", relativeTo: siteURL)?.absoluteURL ?? siteURL
    }

    func setPagePath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        pagePath = trimmed.isEmpty ? "/music" : (trimmed.hasPrefix("/") ? trimmed : "/" + trimmed)
        persistSoon()
    }

    // MARK: - Folder

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose the folder with your recordings. Website only reads it."
        if let folder { panel.directoryURL = folder }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
        persistNow()
        Task { await scanFolder() }
    }

    func scanFolder() async {
        guard let folder, !isScanning else { return }
        isScanning = true
        let pieces = await Task.detached(priority: .userInitiated) {
            MusicLibraryScanner.scan(folder: folder)
        }.value
        library = pieces
        selection = selection.intersection(Set(pieces.map(\.id)))
        isScanning = false
        for piece in comparison.notOnSite.prefix(300) where durations[piece.id] == nil {
            if let seconds = await AudioPreparer.duration(of: piece.url) {
                durations[piece.id] = seconds
            }
        }
    }

    // MARK: - Site

    func readSite() async {
        guard !isReadingSite else { return }
        isReadingSite = true
        defer { isReadingSite = false }
        do {
            let items = try await MusicPageReader().read(pageURL)
            let catalog = MusicCatalog.build(from: items)
            self.catalog = catalog
            catalogNote = catalog.entries.isEmpty ? "No audio players were found on \(pagePath)." : nil
        } catch {
            // Fall back to the page source, whose order can differ from what visitors see.
            do {
                var request = URLRequest(url: pageURL)
                request.setValue(AppInfo.userAgent, forHTTPHeaderField: "User-Agent")
                let (data, _) = try await URLSession.shared.data(for: request)
                let items = MusicCatalog.parseSourceOrder(html: String(decoding: data, as: UTF8.self))
                catalog = MusicCatalog.build(from: items)
                catalogNote = "Read from the page source, so the order may differ from what visitors see."
            } catch {
                errorMessage = "Couldn't read \(pageURL.absoluteString): \(error.localizedDescription)"
                return
            }
        }
        catalogReadAt = Date()
        refreshBatchStatus()
    }

    // MARK: - Second lines

    func subtitle(for piece: LocalPiece) -> String {
        subtitles[piece.normalizedTitle] ?? ""
    }

    func setSubtitle(_ text: String, for piece: LocalPiece) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        subtitles[piece.normalizedTitle] = trimmed.isEmpty ? nil : text
        persistSoon()
    }

    // MARK: - Preparing uploads

    /// Copies or converts the selected pieces into a new upload folder and builds the checklist.
    func prepareSelected() async -> Bool {
        let chosen = comparison.notOnSite.filter { selection.contains($0.id) }
        guard !chosen.isEmpty, !isPreparing else { return false }
        isPreparing = true
        defer { isPreparing = false }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let batchFolder = uploadsRoot.appendingPathComponent(formatter.string(from: Date()), isDirectory: true)
        let catalog = self.catalog ?? MusicCatalog(entries: [])

        let ordered = chosen.sorted { a, b in
            if (a.year ?? 0) != (b.year ?? 0) { return (a.year ?? 0) > (b.year ?? 0) }
            return PieceTitle.comesBefore(a.title, b.title)
        }
        var items: [UploadItem] = []
        for piece in ordered {
            do {
                let file = try await AudioPreparer.prepare(piece, into: batchFolder)
                let subtitle = subtitles[piece.normalizedTitle]
                items.append(UploadItem(
                    title: piece.title,
                    year: piece.year,
                    subtitle: subtitle,
                    file: file,
                    placement: Placement.hint(title: piece.title, year: piece.year, catalog: catalog),
                    durationSeconds: durations[piece.id]
                ))
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        preparedBatch = UploadBatch(folder: batchFolder, items: items, createdAt: Date())
        refreshBatchStatus()
        return true
    }

    func refreshBatchStatus() {
        guard var batch = preparedBatch, let catalog else { return }
        let titles = Set(catalog.entries.map(\.normalizedTitle))
        for index in batch.items.indices {
            batch.items[index].isOnSite = titles.contains(PieceTitle.normalize(batch.items[index].title))
        }
        preparedBatch = batch
    }

    func showBatchInFinder() {
        guard let batch = preparedBatch else { return }
        NSWorkspace.shared.activateFileViewerSelecting(batch.items.map(\.file))
    }

    // MARK: - Saving settings

    private func persistSoon() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        persist?(folder, pagePath, subtitles)
    }
}
