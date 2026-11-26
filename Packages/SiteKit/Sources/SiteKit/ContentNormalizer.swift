import CryptoKit
import Foundation

public enum Hashing {
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(_ text: String) -> String {
        sha256Hex(Data(text.utf8))
    }
}

/// Produces hashes that change when a page's content changes, not when per-request values do.
public enum ContentNormalizer {
    /// Keys whose values differ between requests even when nothing on the page changed.
    /// Tuned against real sites as more appear.
    public static let volatileKeys: Set<String> = [
        "now", "requestId", "crumb", "csrfToken", "nonce", "authenticatedAccount",
        "pageLoadTime", "renderTime", "serverTime", "timestamp", "lastRefreshed",
        "cacheKey", "impersonatedSession", "userAccountsContext", "visitorId"
    ]

    /// Hash of the page data with volatile keys removed and keys sorted. Nil if the data isn't JSON.
    public static func contentHash(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let cleaned = strip(object)
        guard JSONSerialization.isValidJSONObject(cleaned),
              let normalized = try? JSONSerialization.data(withJSONObject: cleaned, options: [.sortedKeys]) else {
            return nil
        }
        return Hashing.sha256Hex(normalized)
    }

    /// Hash of the HTML with scripts and nonces removed and whitespace collapsed.
    public static func markupHash(_ html: String) -> String {
        var text = html
        text = replacing("<script\\b[^>]*>[\\s\\S]*?</script>", in: text, with: "")
        text = replacing("\\snonce=\"[^\"]*\"", in: text, with: "")
        text = replacing("\\s+", in: text, with: " ")
        text = replacing(">\\s+<", in: text, with: "><")
        return Hashing.sha256Hex(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// `collection.title` from a page's JSON, if present.
    public static func collectionTitle(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let collection = object["collection"] as? [String: Any],
              let title = collection["title"] as? String else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func strip(_ value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            var result: [String: Any] = [:]
            for (key, child) in dictionary where !volatileKeys.contains(key) {
                result[key] = strip(child)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { strip($0) }
        }
        return value
    }

    static func replacing(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

/// Removes credentials from anything that might be logged.
public enum Redactor {
    static let patterns: [(String, String)] = [
        ("gh[pousr]_[A-Za-z0-9]{20,}", "[REDACTED]"),
        ("github_pat_[A-Za-z0-9_]{20,}", "[REDACTED]"),
        ("sk-ant-[A-Za-z0-9_\\-]{10,}", "[REDACTED]"),
        ("(?i)(authorization:\\s*(?:bearer|token|basic)\\s+)[^\\s\"']+", "$1[REDACTED]"),
        ("(?i)((?:api[_-]?key|access[_-]?token|token|secret|password)\\s*[=:]\\s*\"?)[^\\s&\"']+", "$1[REDACTED]")
    ]

    public static func redact(_ text: String) -> String {
        var result = text
        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: template)
        }
        return result
    }
}
