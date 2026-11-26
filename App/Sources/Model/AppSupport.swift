import Foundation
import SiteKit

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionString: String { "\(version) (\(build))" }

    /// A Safari user agent with the app's name appended, as browsers and apps usually do.
    static var userAgent: String {
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15 SquarespaceManager/\(version)"
    }
}

struct AppPaths {
    let root: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        root = base.appendingPathComponent("Squarespace Manager", isDirectory: true)
    }

    var sitesFile: URL { root.appendingPathComponent("sites.json") }

    func siteDirectory(_ id: UUID) -> URL {
        root.appendingPathComponent("Sites", isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func snapshotsDirectory(_ id: UUID) -> URL {
        siteDirectory(id).appendingPathComponent("Snapshots", isDirectory: true)
    }
}

/// A connected site, saved in sites.json.
struct SiteRecord: Codable, Identifiable, Hashable {
    var id: UUID
    var url: String
    var name: String
    var plan: SquarespacePlan
    var info: SiteInfo?
    var addedAt: Date

    var homeURL: URL? { URL(string: url) }
}

enum AppError: LocalizedError {
    case invalidAddress
    case unreachable(Int)
    case notSquarespace

    var errorDescription: String? {
        switch self {
        case .invalidAddress:
            return "That doesn't look like a web address. Try something like www.example.com."
        case .unreachable(let status):
            return "The site didn't load (HTTP status \(status))."
        case .notSquarespace:
            return "This site doesn't appear to be built on Squarespace."
        }
    }
}
