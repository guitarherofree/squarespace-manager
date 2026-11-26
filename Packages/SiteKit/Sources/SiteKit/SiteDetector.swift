import Foundation

public enum SquarespaceVersion: String, Codable, Hashable, Sendable {
    case v70 = "7.0"
    case v71 = "7.1"
    case unknown

    public var displayName: String {
        switch self {
        case .v70: return "7.0"
        case .v71: return "7.1"
        case .unknown: return "Unknown"
        }
    }
}

public enum DetectionConfidence: String, Codable, Hashable, Sendable {
    /// Read from Squarespace's own page data.
    case confirmed
    /// Inferred from markup patterns.
    case likely
    case unknown
}

/// What the app could learn about a site from its public home page.
public struct SiteInfo: Codable, Hashable, Sendable {
    public var isSquarespace: Bool
    public var version: SquarespaceVersion
    public var versionConfidence: DetectionConfidence
    public var templateID: String?
    public var siteTitle: String?
    public var websiteID: String?
    public var baseURL: String?
    public var detectedAt: Date

    public init(
        isSquarespace: Bool,
        version: SquarespaceVersion,
        versionConfidence: DetectionConfidence,
        templateID: String? = nil,
        siteTitle: String? = nil,
        websiteID: String? = nil,
        baseURL: String? = nil,
        detectedAt: Date
    ) {
        self.isSquarespace = isSquarespace
        self.version = version
        self.versionConfidence = versionConfidence
        self.templateID = templateID
        self.siteTitle = siteTitle
        self.websiteID = websiteID
        self.baseURL = baseURL
        self.detectedAt = detectedAt
    }
}

/// Reads the JSON object Squarespace assigns to `Static.SQUARESPACE_CONTEXT` in every page.
public enum ContextExtractor {
    public static let marker = "Static.SQUARESPACE_CONTEXT"

    public static func contextJSON(in html: String) -> String? {
        let bytes = Array(html.utf8)
        let markerBytes = Array(marker.utf8)
        guard let markerEnd = firstIndex(of: markerBytes, in: bytes) else { return nil }
        var index = markerEnd
        while index < bytes.count && bytes[index] != UInt8(ascii: "{") {
            // Only whitespace and "=" are expected between the marker and the object.
            let byte = bytes[index]
            if byte != UInt8(ascii: " ") && byte != UInt8(ascii: "=") && byte != UInt8(ascii: "\n")
                && byte != UInt8(ascii: "\t") && byte != UInt8(ascii: "\r") {
                return nil
            }
            index += 1
        }
        guard index < bytes.count else { return nil }
        guard let end = balancedObjectEnd(bytes, start: index) else { return nil }
        return String(decoding: bytes[index...end], as: UTF8.self)
    }

    public static func context(in html: String) -> [String: Any]? {
        guard let json = contextJSON(in: html),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)),
              let dictionary = object as? [String: Any] else { return nil }
        return dictionary
    }

    /// Index just past the first occurrence of `needle`.
    static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count else { return nil }
        let first = needle[0]
        var i = 0
        let last = haystack.count - needle.count
        while i <= last {
            if haystack[i] == first {
                var matched = true
                var j = 1
                while j < needle.count {
                    if haystack[i + j] != needle[j] { matched = false; break }
                    j += 1
                }
                if matched { return i + needle.count }
            }
            i += 1
        }
        return nil
    }

    /// Index of the brace that closes the object opening at `start`, skipping braces inside strings.
    static func balancedObjectEnd(_ bytes: [UInt8], start: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        var i = start
        let quote = UInt8(ascii: "\"")
        let backslash = UInt8(ascii: "\\")
        let open = UInt8(ascii: "{")
        let close = UInt8(ascii: "}")
        while i < bytes.count {
            let byte = bytes[i]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == backslash {
                    escaped = true
                } else if byte == quote {
                    inString = false
                }
            } else if byte == quote {
                inString = true
            } else if byte == open {
                depth += 1
            } else if byte == close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
}

public enum SiteDetector {
    /// Markup patterns that only appear on version 7.1 sites (Fluid Engine and page sections).
    static let version71Markers = ["fluid-engine", "fe-block", "data-fluid-engine"]

    public static func analyze(html: String, now: Date = Date()) -> SiteInfo {
        let lower = html.lowercased()
        let context = ContextExtractor.context(in: html)
        let hasSquarespaceAssets = lower.contains("static1.squarespace.com")
            || lower.contains("assets.squarespace.com")
            || lower.contains("this is squarespace.")
        let isSquarespace = context != nil || hasSquarespaceAssets

        var version = SquarespaceVersion.unknown
        var confidence = DetectionConfidence.unknown
        if let raw = context?["templateVersion"], let parsed = parseVersion(raw) {
            version = parsed
            confidence = .confirmed
        } else if isSquarespace, version71Markers.contains(where: { lower.contains($0) }) {
            version = .v71
            confidence = .likely
        }

        let website = context?["website"] as? [String: Any]
        return SiteInfo(
            isSquarespace: isSquarespace,
            version: version,
            versionConfidence: confidence,
            templateID: context?["templateId"] as? String,
            siteTitle: (website?["siteTitle"] as? String).flatMap(nonEmpty),
            websiteID: website?["id"] as? String,
            baseURL: website?["baseUrl"] as? String,
            detectedAt: now
        )
    }

    static func parseVersion(_ raw: Any) -> SquarespaceVersion? {
        let text: String
        if let string = raw as? String {
            text = string
        } else if let number = raw as? NSNumber {
            text = number.stringValue
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("7.1") { return .v71 }
        if trimmed == "7" || trimmed == "7.0" { return .v70 }
        return nil
    }

    static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
