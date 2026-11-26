import Foundation

/// Sitemap parsing and the file names used for pages in a snapshot.
public struct Sitemap: Equatable, Sendable {
    /// True for a sitemap index, whose locations are other sitemaps.
    public var isIndex: Bool
    public var locations: [URL]

    public static func parse(_ xml: String) -> Sitemap {
        let isIndex = xml.range(of: "<sitemapindex", options: .caseInsensitive) != nil
        var locations: [URL] = []
        guard let regex = try? NSRegularExpression(pattern: "<loc>\\s*([^<]+?)\\s*</loc>", options: [.caseInsensitive]) else {
            return Sitemap(isIndex: isIndex, locations: [])
        }
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        for match in regex.matches(in: xml, options: [], range: range) {
            guard let captured = Range(match.range(at: 1), in: xml) else { continue }
            let decoded = HTMLText.decodeEntities(String(xml[captured]))
            if let url = URL(string: decoded) { locations.append(url) }
        }
        return Sitemap(isIndex: isIndex, locations: locations)
    }
}

public enum PagePaths {
    /// A file-safe name for a page: "/" becomes "home", "/blog/post" becomes "blog__post".
    public static func slug(for url: URL) -> String {
        let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
        if parts.isEmpty { return "home" }
        let joined = parts.joined(separator: "__").lowercased()
        var result = ""
        for scalar in joined.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_" {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("-")
            }
        }
        if result.count > 120 { result = String(result.prefix(120)) }
        return result
    }

    public static func uniqueSlug(for url: URL, used: inout Set<String>) -> String {
        let base = slug(for: url)
        var candidate = base
        var counter = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        used.insert(candidate)
        return candidate
    }

    /// The page's public data URL (`?format=json-pretty`), keeping any other query items.
    public static func jsonURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "format" }
        items.append(URLQueryItem(name: "format", value: "json-pretty"))
        components.queryItems = items
        return components.url ?? url
    }
}

public enum HTMLText {
    public static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let replacements: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
            ("&apos;", "'"), ("&#x27;", "'"), ("&nbsp;", " "), ("&amp;", "&")
        ]
        for (entity, character) in replacements {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    /// The contents of the page's `<title>` element.
    public static func title(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([\\s\\S]*?)</title>", options: [.caseInsensitive]) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: range),
              let captured = Range(match.range(at: 1), in: html) else { return nil }
        let title = decodeEntities(String(html[captured]))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}
