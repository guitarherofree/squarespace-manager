import Foundation

/// Turns what someone types ("freemanedwards.com") into a site root URL.
public enum SiteAddress {
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host, host.contains(".") else { return nil }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = "/"
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Scheme, host and port of `url`, with the path set to "/".
    public static func root(of url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url }
        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url ?? url
    }

    /// Host without a leading "www.", lowercased.
    public static func bareHost(_ url: URL) -> String {
        let host = (url.host ?? "").lowercased()
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func sameSite(_ a: URL, _ b: URL) -> Bool {
        bareHost(a) == bareHost(b)
    }

    public static func samePage(_ a: URL, _ b: URL) -> Bool {
        guard sameSite(a, b) else { return false }
        return trimmedPath(a) == trimmedPath(b)
    }

    static func trimmedPath(_ url: URL) -> String {
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
