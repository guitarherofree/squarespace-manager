import Foundation

/// One page as it was when a snapshot was taken.
public struct PageRecord: Codable, Hashable, Sendable {
    public var url: String
    public var slug: String
    public var title: String?
    public var httpStatus: Int
    /// Hash of the page's public data with per-request values removed.
    public var contentHash: String?
    /// Hash of the page's HTML with scripts removed.
    public var markupHash: String?
    public var error: String?

    public init(url: String, slug: String, title: String? = nil, httpStatus: Int = 0,
                contentHash: String? = nil, markupHash: String? = nil, error: String? = nil) {
        self.url = url
        self.slug = slug
        self.title = title
        self.httpStatus = httpStatus
        self.contentHash = contentHash
        self.markupHash = markupHash
        self.error = error
    }
}

public struct SnapshotManifest: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var createdAt: Date
    public var siteURL: String
    public var siteInfo: SiteInfo
    public var cssHash: String?
    public var pages: [PageRecord]
    public var appVersion: String?

    public init(id: String, createdAt: Date, siteURL: String, siteInfo: SiteInfo,
                cssHash: String?, pages: [PageRecord], appVersion: String?) {
        self.id = id
        self.createdAt = createdAt
        self.siteURL = siteURL
        self.siteInfo = siteInfo
        self.cssHash = cssHash
        self.pages = pages
        self.appVersion = appVersion
    }

    public var failedPageCount: Int { pages.filter { $0.error != nil || !(200..<300).contains($0.httpStatus) }.count }
}

public struct SnapshotProgress: Equatable, Sendable {
    public var completed: Int
    public var total: Int
    public var message: String

    public init(completed: Int, total: Int, message: String) {
        self.completed = completed
        self.total = total
        self.message = message
    }

    public var fraction: Double? {
        total > 0 ? Double(completed) / Double(total) : nil
    }
}

public enum SnapshotError: LocalizedError, Equatable {
    case homePageUnavailable(Int)

    public var errorDescription: String? {
        switch self {
        case .homePageUnavailable(let status):
            return "The home page didn't load (HTTP status \(status))."
        }
    }
}

/// Snapshots live in folders named by time, each with a manifest.json and the saved files.
public struct SnapshotStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public static func makeID(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss.SSS'Z'"
        return formatter.string(from: date)
    }

    public func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    public func prepare(_ id: String) throws {
        try FileManager.default.createDirectory(
            at: directory(for: id).appendingPathComponent("pages", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    public func writeFile(_ data: Data, snapshotID: String, relativePath: String) throws {
        let url = directory(for: snapshotID).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    public func writeManifest(_ manifest: SnapshotManifest) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try writeFile(data, snapshotID: manifest.id, relativePath: "manifest.json")
    }

    /// All readable snapshots, newest first.
    public func list() throws -> [SnapshotManifest] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let folders = try fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var manifests: [SnapshotManifest] = []
        for folder in folders {
            let manifestURL = folder.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? decoder.decode(SnapshotManifest.self, from: data) else { continue }
            manifests.append(manifest)
        }
        return manifests.sorted { $0.createdAt > $1.createdAt }
    }
}

/// Reads a site page by page and saves a snapshot.
public struct SnapshotService: Sendable {
    public let client: HTTPClient
    public let store: SnapshotStore
    public var maxPages: Int
    /// Pause before each request, in nanoseconds, so the site isn't hit hard.
    public var requestDelay: UInt64

    public init(client: HTTPClient, store: SnapshotStore, maxPages: Int = 300, requestDelay: UInt64 = 250_000_000) {
        self.client = client
        self.store = store
        self.maxPages = maxPages
        self.requestDelay = requestDelay
    }

    public func takeSnapshot(
        siteURL: URL,
        appVersion: String? = nil,
        now: Date = Date(),
        progress: @escaping @Sendable (SnapshotProgress) -> Void = { _ in }
    ) async throws -> SnapshotManifest {
        progress(SnapshotProgress(completed: 0, total: 0, message: "Reading the home page"))
        let requestedRoot = SiteAddress.root(of: siteURL)
        let home = try await client.get(requestedRoot)
        guard home.isSuccess else { throw SnapshotError.homePageUnavailable(home.status) }
        let root = SiteAddress.root(of: home.url)
        let info = SiteDetector.analyze(html: home.text, now: now)

        progress(SnapshotProgress(completed: 0, total: 0, message: "Finding pages"))
        var pageURLs = await discoverPages(root: root)
        pageURLs.removeAll { SiteAddress.samePage($0, root) }
        pageURLs.insert(root, at: 0)
        if pageURLs.count > maxPages {
            pageURLs = Array(pageURLs.prefix(maxPages))
        }

        let id = SnapshotStore.makeID(for: now)
        try store.prepare(id)
        var records: [PageRecord] = []
        var usedSlugs = Set<String>()

        for (index, pageURL) in pageURLs.enumerated() {
            try Task.checkCancellation()
            let label = pageURL.path.isEmpty ? "/" : pageURL.path
            progress(SnapshotProgress(completed: index, total: pageURLs.count, message: label))
            let slug = PagePaths.uniqueSlug(for: pageURL, used: &usedSlugs)
            var record = PageRecord(url: pageURL.absoluteString, slug: slug)
            do {
                let page: HTTPResponse
                if index == 0 {
                    page = home
                } else {
                    page = try await fetch(pageURL)
                }
                record.httpStatus = page.status
                if page.isSuccess {
                    try store.writeFile(page.data, snapshotID: id, relativePath: "pages/\(slug).html")
                    record.markupHash = ContentNormalizer.markupHash(page.text)
                    record.title = HTMLText.title(in: page.text)
                    let data = try await fetch(PagePaths.jsonURL(for: pageURL))
                    if data.isSuccess, let hash = ContentNormalizer.contentHash(data.data) {
                        try store.writeFile(data.data, snapshotID: id, relativePath: "pages/\(slug).json")
                        record.contentHash = hash
                        if let title = ContentNormalizer.collectionTitle(data.data) {
                            record.title = title
                        }
                    }
                }
            } catch {
                if Task.isCancelled { throw CancellationError() }
                record.error = error.localizedDescription
            }
            records.append(record)
        }

        try Task.checkCancellation()
        progress(SnapshotProgress(completed: pageURLs.count, total: pageURLs.count, message: "Saving site CSS"))
        var cssHash: String?
        if let cssURL = URL(string: "site.css?minify=false", relativeTo: root)?.absoluteURL,
           let css = try? await fetch(cssURL), css.isSuccess {
            try store.writeFile(css.data, snapshotID: id, relativePath: "site.css")
            cssHash = Hashing.sha256Hex(css.data)
        }

        let manifest = SnapshotManifest(
            id: id,
            createdAt: now,
            siteURL: root.absoluteString,
            siteInfo: info,
            cssHash: cssHash,
            pages: records,
            appVersion: appVersion
        )
        try store.writeManifest(manifest)
        progress(SnapshotProgress(completed: pageURLs.count, total: pageURLs.count, message: "Done"))
        return manifest
    }

    /// Page URLs from sitemap.xml (following one level of sitemap index), same site only, in order.
    func discoverPages(root: URL) async -> [URL] {
        guard let sitemapURL = URL(string: "sitemap.xml", relativeTo: root)?.absoluteURL,
              let response = try? await fetch(sitemapURL), response.isSuccess else { return [] }
        let sitemap = Sitemap.parse(response.text)
        var candidates: [URL] = []
        if sitemap.isIndex {
            for child in sitemap.locations.prefix(10) {
                if let childResponse = try? await fetch(child), childResponse.isSuccess {
                    candidates.append(contentsOf: Sitemap.parse(childResponse.text).locations)
                }
            }
        } else {
            candidates = sitemap.locations
        }
        var seen = Set<String>()
        var result: [URL] = []
        for url in candidates where SiteAddress.sameSite(url, root) {
            let key = SiteAddress.bareHost(url) + SiteAddress.trimmedPath(url)
            if seen.insert(key).inserted { result.append(url) }
        }
        return result
    }

    private func fetch(_ url: URL) async throws -> HTTPResponse {
        if requestDelay > 0 {
            try await Task.sleep(nanoseconds: requestDelay)
        }
        return try await client.get(url)
    }
}

/// What changed between two snapshots.
public struct SnapshotDiff: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case added, removed, contentChanged, markupChanged, unchanged, failed

        public var label: String {
            switch self {
            case .added: return "New page"
            case .removed: return "Page removed"
            case .contentChanged: return "Content changed"
            case .markupChanged: return "Markup changed"
            case .unchanged: return "Unchanged"
            case .failed: return "Couldn't read"
            }
        }
    }

    public struct Entry: Equatable, Identifiable, Sendable {
        public var id: String { url }
        public var url: String
        public var title: String?
        public var kind: Kind
    }

    public var entries: [Entry]
    public var cssChanged: Bool
    /// True when there was no earlier snapshot to compare with.
    public var isBaseline: Bool

    public var changedEntries: [Entry] {
        entries.filter { $0.kind != .unchanged }
    }

    public static func compare(old: SnapshotManifest?, new: SnapshotManifest) -> SnapshotDiff {
        guard let old else {
            let entries = new.pages.map { Entry(url: $0.url, title: $0.title, kind: $0.error == nil ? .unchanged : .failed) }
            return SnapshotDiff(entries: entries, cssChanged: false, isBaseline: true)
        }
        var oldByURL: [String: PageRecord] = [:]
        for page in old.pages where oldByURL[page.url] == nil {
            oldByURL[page.url] = page
        }
        var entries: [Entry] = []
        for page in new.pages {
            let kind: Kind
            if page.error != nil || !(200..<300).contains(page.httpStatus) {
                kind = .failed
            } else if let before = oldByURL[page.url] {
                if let a = before.contentHash, let b = page.contentHash, a != b {
                    kind = .contentChanged
                } else if before.markupHash != page.markupHash {
                    kind = .markupChanged
                } else {
                    kind = .unchanged
                }
            } else {
                kind = .added
            }
            entries.append(Entry(url: page.url, title: page.title, kind: kind))
        }
        let newURLs = Set(new.pages.map(\.url))
        for page in old.pages where !newURLs.contains(page.url) {
            entries.append(Entry(url: page.url, title: page.title, kind: .removed))
        }
        let cssChanged: Bool
        if let a = old.cssHash, let b = new.cssHash {
            cssChanged = a != b
        } else {
            cssChanged = false
        }
        return SnapshotDiff(entries: entries, cssChanged: cssChanged, isBaseline: false)
    }
}
