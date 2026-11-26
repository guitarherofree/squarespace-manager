import Foundation

/// Where updates come from and what to look for.
public struct UpdaterConfiguration: Sendable {
    /// "owner/repo" on GitHub.
    public var repository: String
    /// The app's name as used in asset names and folders, e.g. "Website".
    public var appName: String
    public var currentVersion: String
    public var bundleIdentifier: String
    /// Architecture in the asset name. The standard is arm64.
    public var architecture: String

    public init(repository: String, appName: String, currentVersion: String,
                bundleIdentifier: String, architecture: String = "arm64") {
        self.repository = repository
        self.appName = appName
        self.currentVersion = currentVersion
        self.bundleIdentifier = bundleIdentifier
        self.architecture = architecture
    }

    /// The release asset this app installs, e.g. "Website-0.2.0-mac-arm64.zip".
    public func assetName(for version: String) -> String {
        "\(appName)-\(version)-mac-\(architecture).zip"
    }
}

/// The parts of GitHub's release JSON the updater uses.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public let name: String
        public let size: Int
        public let browserDownloadURL: URL
        /// API URL; used with a token for private repositories.
        public let apiURL: URL
        /// "sha256:<hex>" when GitHub has computed it.
        public let digest: String?

        enum CodingKeys: String, CodingKey {
            case name, size, digest
            case browserDownloadURL = "browser_download_url"
            case apiURL = "url"
        }

        public var sha256: String? {
            guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
            return String(digest.dropFirst("sha256:".count)).lowercased()
        }
    }

    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL?
    public let draft: Bool
    public let prerelease: Bool
    public let publishedAt: Date?
    public let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case name, body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// The tag without a leading "v".
    public var version: String {
        tagName.hasPrefix("v") || tagName.hasPrefix("V") ? String(tagName.dropFirst()) : tagName
    }

    public static func decode(_ data: Data) throws -> GitHubRelease {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubRelease.self, from: data)
    }

    /// The zip for this app: the exact standard name first, then any Mac zip for the architecture.
    public func asset(for configuration: UpdaterConfiguration) -> Asset? {
        let wanted = configuration.assetName(for: version).lowercased()
        if let exact = assets.first(where: { $0.name.lowercased() == wanted }) {
            return exact
        }
        let arch = configuration.architecture.lowercased()
        return assets.first { asset in
            let name = asset.name.lowercased()
            return name.hasSuffix(".zip") && name.contains("mac") && name.contains(arch)
        }
    }
}

public enum VersionComparison {
    /// Compares dotted versions numerically ("0.10.0" > "0.9.1"). Text after "-" or "+" is ignored.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let left = components(a)
        let right = components(b)
        for index in 0..<max(left.count, right.count) {
            let x = index < left.count ? left[index] : 0
            let y = index < right.count ? right[index] : 0
            if x < y { return .orderedAscending }
            if x > y { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    static func components(_ version: String) -> [Int] {
        var text = version.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        if let cut = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<cut])
        }
        return text.split(separator: ".").map { Int($0) ?? 0 }
    }
}
