import Foundation

// MARK: - Reading the site's music page

/// One block on the music page, as the browser lays it out.
public struct MusicPageItem: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case audio
    }

    public var kind: Kind
    /// Text of a text block, or the player's title.
    public var text: String
    /// The player's second line (Squarespace calls it "author").
    public var subtitle: String?
    public var assetURL: String?
    public var durationMilliseconds: Int?
    public var designStyle: String?
    /// Position on the page; items are sorted top to bottom, then left to right.
    public var y: Double
    public var x: Double

    public init(kind: Kind, text: String, subtitle: String? = nil, assetURL: String? = nil,
                durationMilliseconds: Int? = nil, designStyle: String? = nil, y: Double, x: Double) {
        self.kind = kind
        self.text = text
        self.subtitle = subtitle
        self.assetURL = assetURL
        self.durationMilliseconds = durationMilliseconds
        self.designStyle = designStyle
        self.y = y
        self.x = x
    }
}

/// A piece on the site's music page.
public struct CatalogEntry: Equatable, Identifiable, Sendable {
    public var id: String { "\(position)-\(title)" }
    public var title: String
    public var subtitle: String?
    /// The year heading the piece sits under, if any.
    public var year: Int?
    public var assetURL: String?
    public var durationSeconds: Int?
    public var designStyle: String?
    /// Position on the page, from the top.
    public var position: Int

    public var normalizedTitle: String { PieceTitle.normalize(title) }
}

/// The site's music page as a list of pieces under year headings, in the order visitors see them.
public struct MusicCatalog: Equatable, Sendable {
    public var entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
    }

    /// Years with headings on the page, newest first.
    public var years: [Int] {
        Array(Set(entries.compactMap(\.year))).sorted(by: >)
    }

    public func entries(in year: Int?) -> [CatalogEntry] {
        entries.filter { $0.year == year }
    }

    /// Builds the catalog from blocks positioned by the browser. A text block that is just a
    /// four-digit year starts a new year group.
    public static func build(from items: [MusicPageItem]) -> MusicCatalog {
        let ordered = items.sorted { a, b in
            if abs(a.y - b.y) > 2 { return a.y < b.y }
            return a.x < b.x
        }
        var year: Int?
        var entries: [CatalogEntry] = []
        for item in ordered {
            switch item.kind {
            case .text:
                if let heading = PieceTitle.yearHeading(item.text) {
                    year = heading
                }
            case .audio:
                let title = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let subtitle = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(CatalogEntry(
                    title: title.isEmpty ? "Untitled" : title,
                    subtitle: (subtitle?.isEmpty ?? true) ? nil : subtitle,
                    year: year,
                    assetURL: item.assetURL,
                    durationSeconds: item.durationMilliseconds.map { $0 / 1000 },
                    designStyle: item.designStyle,
                    position: entries.count
                ))
            }
        }
        return MusicCatalog(entries: entries)
    }

    /// Reads the page's HTML in source order. Squarespace 7.1 lays blocks out with a grid, so the
    /// source order can differ from what visitors see; the app prefers browser positions.
    public static func parseSourceOrder(html: String) -> [MusicPageItem] {
        let pattern = "<div class=\"sqs-audio-embed\"([^>]*)>|data-sqsp-text-block-content[^>]*>([\\s\\S]*?)</div>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var items: [MusicPageItem] = []
        for (index, match) in regex.matches(in: html, options: [], range: range).enumerated() {
            if let attributesRange = Range(match.range(at: 1), in: html) {
                let attributes = parseAttributes(String(html[attributesRange]))
                items.append(MusicPageItem(
                    kind: .audio,
                    text: HTMLText.decodeEntities(attributes["data-title"] ?? ""),
                    subtitle: attributes["data-author"].map(HTMLText.decodeEntities),
                    assetURL: attributes["data-asset-url"],
                    durationMilliseconds: attributes["data-length-in-milli-seconds"].flatMap { Int($0) },
                    designStyle: attributes["data-design-style"],
                    y: Double(index),
                    x: 0
                ))
            } else if let contentRange = Range(match.range(at: 2), in: html) {
                let text = stripTags(String(html[contentRange]))
                items.append(MusicPageItem(kind: .text, text: text, y: Double(index), x: 0))
            }
        }
        return items
    }

    static func parseAttributes(_ text: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(pattern: "([a-zA-Z0-9-]+)=\"([^\"]*)\"", options: []) else { return [:] }
        var result: [String: String] = [:]
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for match in regex.matches(in: text, options: [], range: range) {
            guard let key = Range(match.range(at: 1), in: text), let value = Range(match.range(at: 2), in: text) else { continue }
            result[String(text[key])] = String(text[value])
        }
        return result
    }

    static func stripTags(_ html: String) -> String {
        let withoutTags = ContentNormalizer.replacing("<[^>]+>", in: html, with: " ")
        return HTMLText.decodeEntities(withoutTags)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Titles and years

public enum PieceTitle {
    /// The year of a heading that is just a year ("2022", " 2022 ").
    public static func yearHeading(_ text: String) -> Int? {
        let trimmed = text.replacingOccurrences(of: "\u{00A0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 4, let year = Int(trimmed), (1900...2100).contains(year) else { return nil }
        return year
    }

    /// Lowercased, without a "(2022)" year, punctuation collapsed to single spaces.
    public static func normalize(_ title: String) -> String {
        var text = title.lowercased()
        text = ContentNormalizer.replacing("\\(\\s*(19|20)\\d{2}\\s*\\)", in: text, with: " ")
        text = ContentNormalizer.replacing("[^\\p{L}\\p{N}]+", in: text, with: " ")
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// The display title for a file: its name without the extension or a trailing "(2022)".
    public static func title(fromFileName name: String) -> String {
        var base = (name as NSString).deletingPathExtension
        base = ContentNormalizer.replacing("\\s*\\(\\s*(19|20)\\d{2}\\s*\\)\\s*$", in: base, with: "")
        return base.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A year from "2023 Work 4" or "For Violin (2022)".
    public static func year(fromFileName name: String) -> Int? {
        let base = (name as NSString).deletingPathExtension
        if let leading = firstMatch("^\\s*((19|20)\\d{2})\\b", in: base) { return Int(leading) }
        if let paren = firstMatch("\\(\\s*((19|20)\\d{2})\\s*\\)", in: base) { return Int(paren) }
        return nil
    }

    /// The N in "Work N", used to order pieces within a year (higher first).
    public static func workNumber(_ title: String) -> Int? {
        firstMatch("(?i)\\bwork\\s+(\\d+)", in: title).flatMap { Int($0) }
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let captured = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captured])
    }

    /// Order within a year: named works first, then Work numbers from highest to lowest.
    static func sortKey(_ title: String) -> (Int, Int, String) {
        if let number = workNumber(title) {
            return (1, -number, normalize(title))
        }
        return (0, 0, normalize(title))
    }

    static func comesBefore(_ a: String, _ b: String) -> Bool {
        let x = sortKey(a)
        let y = sortKey(b)
        if x.0 != y.0 { return x.0 < y.0 }
        if x.1 != y.1 { return x.1 < y.1 }
        return x.2 < y.2
    }
}

// MARK: - The folder of recordings

public struct LocalPiece: Equatable, Identifiable, Sendable {
    public var id: String { url.path }
    public var url: URL
    public var title: String
    public var year: Int?
    /// Where the year came from: the file name, its folder, or the file's date.
    public var yearSource: YearSource
    public var sizeBytes: Int64
    public var otherFormats: [String]

    public enum YearSource: String, Sendable {
        case fileName, folder, fileDate, none
    }

    public var fileExtension: String { url.pathExtension.lowercased() }
    public var normalizedTitle: String { PieceTitle.normalize(title) }
}

public enum MusicLibraryScanner {
    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf"]
    /// When the same piece is in several formats, the first of these is used.
    static let preference = ["mp3", "m4a", "aac", "wav", "aiff", "aif", "flac", "caf"]

    public static func scan(folder: URL) -> [LocalPiece] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .creationDateKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var byTitle: [String: [LocalPiece]] = [:]
        for case let url as URL in enumerator {
            guard audioExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            var year = PieceTitle.year(fromFileName: name)
            var source = LocalPiece.YearSource.fileName
            if year == nil, let folderYear = PieceTitle.yearHeading(url.deletingLastPathComponent().lastPathComponent) {
                year = folderYear
                source = .folder
            }
            if year == nil, let date = values.creationDate ?? values.contentModificationDate {
                year = Calendar(identifier: .gregorian).component(.year, from: date)
                source = .fileDate
            }
            let piece = LocalPiece(
                url: url,
                title: PieceTitle.title(fromFileName: name),
                year: year,
                yearSource: year == nil ? .none : source,
                sizeBytes: Int64(values.fileSize ?? 0),
                otherFormats: []
            )
            byTitle[piece.normalizedTitle, default: []].append(piece)
        }
        var pieces: [LocalPiece] = []
        for (_, group) in byTitle {
            let sorted = group.sorted { rank($0.fileExtension) < rank($1.fileExtension) }
            guard var best = sorted.first else { continue }
            best.otherFormats = sorted.dropFirst().map(\.fileExtension)
            pieces.append(best)
        }
        return pieces.sorted { a, b in
            if (a.year ?? 0) != (b.year ?? 0) { return (a.year ?? 0) > (b.year ?? 0) }
            return PieceTitle.comesBefore(a.title, b.title)
        }
    }

    static func rank(_ fileExtension: String) -> Int {
        preference.firstIndex(of: fileExtension) ?? preference.count
    }
}

// MARK: - Comparing the folder with the site

public struct MusicComparison: Sendable {
    public struct Match: Equatable, Identifiable, Sendable {
        public var id: String { entry.id }
        public var entry: CatalogEntry
        public var local: LocalPiece?
    }

    /// Pieces in the folder that aren't on the site.
    public var notOnSite: [LocalPiece]
    /// Every piece on the site, with its file in the folder when there is one.
    public var onSite: [Match]
    /// Pieces on the site with no file in the folder.
    public var siteOnly: [CatalogEntry] {
        onSite.filter { $0.local == nil }.map(\.entry)
    }

    public init(library: [LocalPiece], catalog: MusicCatalog?) {
        let entries = catalog?.entries ?? []
        var localByTitle: [String: LocalPiece] = [:]
        for piece in library where localByTitle[piece.normalizedTitle] == nil {
            localByTitle[piece.normalizedTitle] = piece
        }
        let siteTitles = Set(entries.map(\.normalizedTitle))
        notOnSite = library.filter { !siteTitles.contains($0.normalizedTitle) }
        onSite = entries.map { Match(entry: $0, local: localByTitle[$0.normalizedTitle]) }
    }
}

/// Where a new piece goes on the page, in words for the checklist.
public enum Placement {
    public static func hint(title: String, year: Int?, catalog: MusicCatalog) -> String {
        guard let year else {
            return "Year unknown: place it where it belongs."
        }
        let inYear = catalog.entries(in: year)
        if !inYear.isEmpty {
            if let next = inYear.first(where: { PieceTitle.comesBefore(title, $0.title) }) {
                return "Under \(year), above \"\(next.title)\""
            }
            return "Under \(year), below \"\(inYear.last?.title ?? "")\""
        }
        let years = catalog.years
        if let newest = years.first, year > newest {
            return "New \(year) heading at the top, above \(newest)"
        }
        if let older = years.first(where: { $0 < year }) {
            return "New \(year) heading, above \(older)"
        }
        if let oldest = years.last {
            return "New \(year) heading at the bottom, below \(oldest)"
        }
        return "New \(year) heading"
    }
}

// MARK: - Getting files ready for Squarespace

public enum UploadPlan: Equatable, Sendable {
    /// Already an MP3 or M4A under the size limit.
    case copy
    /// Converted to AAC in an M4A file.
    case convertToM4A

    /// Squarespace's audio block takes MP3 or M4A files of 160 MB or less.
    public static let maximumBytes: Int64 = 160 * 1_000_000

    public static func plan(for piece: LocalPiece) -> UploadPlan {
        let supported = piece.fileExtension == "mp3" || piece.fileExtension == "m4a"
        return supported && piece.sizeBytes <= maximumBytes ? .copy : .convertToM4A
    }

    /// The name the prepared file gets, so the player's default title matches the piece.
    public static func fileName(for piece: LocalPiece) -> String {
        let safe = piece.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        switch plan(for: piece) {
        case .copy: return "\(safe).\(piece.fileExtension)"
        case .convertToM4A: return "\(safe).m4a"
        }
    }
}
