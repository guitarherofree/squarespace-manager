import Foundation
import Observation
import SiteKit

@MainActor
@Observable
final class AppModel {
    var sites: [SiteRecord] = []
    var selectedSiteID: UUID?
    var isAddingSite = false
    var errorMessage: String?

    /// Progress of running snapshots, by site. Present only while one is running.
    var snapshotProgress: [UUID: SnapshotProgress] = [:]
    /// Saved snapshots by site, newest first.
    var manifests: [UUID: [SnapshotManifest]] = [:]
    /// Sites whose detection is being refreshed.
    var refreshing: Set<UUID> = []

    private let paths = AppPaths()
    /// The site whose prepared files the Add to Squarespace window shows.
    var editorSiteID: UUID?

    @ObservationIgnored private var snapshotTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var musicModels: [UUID: MusicModel] = [:]
    private let client: HTTPClient = URLSessionHTTPClient(userAgent: AppInfo.userAgent)

    init() {
        paths.migrateLegacyData()
        loadSites()
        for site in sites {
            reloadManifests(for: site.id)
        }
        selectedSiteID = sites.first?.id
    }

    func site(_ id: UUID?) -> SiteRecord? {
        guard let id else { return nil }
        return sites.first { $0.id == id }
    }

    // MARK: - Sites

    func addSite(address: String, plan: SquarespacePlan) async throws {
        guard let url = SiteAddress.normalize(address) else { throw AppError.invalidAddress }
        let response = try await client.get(url)
        guard response.isSuccess else { throw AppError.unreachable(response.status) }
        let info = SiteDetector.analyze(html: response.text)
        guard info.isSquarespace else { throw AppError.notSquarespace }
        let root = SiteAddress.root(of: response.url)

        if let existing = sites.first(where: { SiteAddress.sameSite(URL(string: $0.url) ?? root, root) }) {
            selectedSiteID = existing.id
            return
        }
        let record = SiteRecord(
            id: UUID(),
            url: root.absoluteString,
            name: info.siteTitle ?? root.host ?? address,
            plan: plan,
            info: info,
            addedAt: Date()
        )
        sites.append(record)
        manifests[record.id] = []
        saveSites()
        selectedSiteID = record.id
    }

    func refreshDetection(for id: UUID) async {
        guard let url = self.site(id)?.homeURL, !refreshing.contains(id) else { return }
        refreshing.insert(id)
        defer { refreshing.remove(id) }
        do {
            let response = try await client.get(url)
            guard response.isSuccess else { throw AppError.unreachable(response.status) }
            let info = SiteDetector.analyze(html: response.text)
            if let index = sites.firstIndex(where: { $0.id == id }) {
                sites[index].info = info
                saveSites()
            }
        } catch {
            errorMessage = "Couldn't check the site: \(error.localizedDescription)"
        }
    }

    func setPlan(_ plan: SquarespacePlan, for id: UUID) {
        guard let index = sites.firstIndex(where: { $0.id == id }), sites[index].plan != plan else { return }
        sites[index].plan = plan
        saveSites()
    }

    /// Removes the site from the list. Its snapshots stay on disk.
    func removeSite(_ id: UUID) {
        snapshotTasks[id]?.cancel()
        sites.removeAll { $0.id == id }
        musicModels[id] = nil
        if editorSiteID == id { editorSiteID = nil }
        manifests[id] = nil
        if selectedSiteID == id { selectedSiteID = sites.first?.id }
        saveSites()
    }

    /// The Music tab's model for a site, created on first use.
    func music(for id: UUID) -> MusicModel? {
        if let existing = musicModels[id] { return existing }
        guard let site = self.site(id), let url = site.homeURL else { return nil }
        let music = MusicModel(
            siteID: id,
            siteURL: url,
            folder: site.musicFolder.map { URL(fileURLWithPath: $0, isDirectory: true) },
            pagePath: site.musicPagePath ?? "/music",
            subtitles: site.musicSubtitles ?? [:],
            uploadsRoot: paths.uploadsDirectory
        )
        music.persist = { [weak self] folder, pagePath, subtitles in
            self?.saveMusicSettings(for: id, folder: folder, pagePath: pagePath, subtitles: subtitles)
        }
        musicModels[id] = music
        return music
    }

    private func saveMusicSettings(for id: UUID, folder: URL?, pagePath: String, subtitles: [String: String]) {
        guard let index = sites.firstIndex(where: { $0.id == id }) else { return }
        sites[index].musicFolder = folder?.path
        sites[index].musicPagePath = pagePath
        sites[index].musicSubtitles = subtitles
        saveSites()
    }

    func snapshotsFolder(for id: UUID) -> URL {
        paths.snapshotsDirectory(id)
    }

    // MARK: - Snapshots

    func startSnapshot(for id: UUID) {
        guard snapshotTasks[id] == nil, let url = self.site(id)?.homeURL else { return }
        snapshotProgress[id] = SnapshotProgress(completed: 0, total: 0, message: "Starting")
        let service = SnapshotService(client: client, store: SnapshotStore(root: paths.snapshotsDirectory(id)))
        let appVersion = AppInfo.versionString
        let handler: @Sendable (SnapshotProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                self?.updateProgress(progress, for: id)
            }
        }
        snapshotTasks[id] = Task { [weak self] in
            do {
                let manifest = try await service.takeSnapshot(siteURL: url, appVersion: appVersion, progress: handler)
                self?.finishSnapshot(for: id, manifest: manifest, error: nil)
            } catch {
                self?.finishSnapshot(for: id, manifest: nil, error: error)
            }
        }
    }

    func cancelSnapshot(for id: UUID) {
        snapshotTasks[id]?.cancel()
    }

    private func updateProgress(_ progress: SnapshotProgress, for id: UUID) {
        guard snapshotTasks[id] != nil else { return }
        snapshotProgress[id] = progress
    }

    private func finishSnapshot(for id: UUID, manifest: SnapshotManifest?, error: Error?) {
        snapshotTasks[id] = nil
        snapshotProgress[id] = nil
        if let manifest, let index = sites.firstIndex(where: { $0.id == id }) {
            sites[index].info = manifest.siteInfo
            saveSites()
        }
        reloadManifests(for: id)
        if let error, !(error is CancellationError), !Task.isCancelled {
            if (error as? URLError)?.code == .cancelled { return }
            errorMessage = "The snapshot didn't finish: \(error.localizedDescription)"
        }
    }

    func reloadManifests(for id: UUID) {
        let store = SnapshotStore(root: paths.snapshotsDirectory(id))
        manifests[id] = (try? store.list()) ?? []
    }

    /// The diff between a snapshot and the one taken before it.
    func diff(for snapshotID: String, site id: UUID) -> SnapshotDiff? {
        let list = manifests[id] ?? []
        guard let index = list.firstIndex(where: { $0.id == snapshotID }) else { return nil }
        let previous = index + 1 < list.count ? list[index + 1] : nil
        return SnapshotDiff.compare(old: previous, new: list[index])
    }

    // MARK: - Persistence

    private func loadSites() {
        guard let data = try? Data(contentsOf: paths.sitesFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([SiteRecord].self, from: data) {
            sites = decoded
        }
    }

    private func saveSites() {
        do {
            try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(sites).write(to: paths.sitesFile, options: .atomic)
        } catch {
            errorMessage = "Couldn't save your site list: \(error.localizedDescription)"
        }
    }
}
