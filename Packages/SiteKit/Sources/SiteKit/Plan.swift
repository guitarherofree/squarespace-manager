import Foundation

/// The site's Squarespace plan. Not public, so the person picks it once.
public enum SquarespacePlan: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case unknown
    case basic
    case core
    case plus
    case advanced
    case legacyPersonal
    case legacyBusiness
    case legacyCommerceBasic
    case legacyCommerceAdvanced

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .unknown: return "Not set"
        case .basic: return "Basic"
        case .core: return "Core"
        case .plus: return "Plus"
        case .advanced: return "Advanced"
        case .legacyPersonal: return "Personal (legacy)"
        case .legacyBusiness: return "Business (legacy)"
        case .legacyCommerceBasic: return "Commerce Basic (legacy)"
        case .legacyCommerceAdvanced: return "Commerce Advanced (legacy)"
        }
    }

    /// Code Injection is on Core, Plus, Advanced and the legacy Business and Commerce plans.
    public var hasCodeInjection: Bool {
        switch self {
        case .core, .plus, .advanced, .legacyBusiness, .legacyCommerceBasic, .legacyCommerceAdvanced:
            return true
        case .unknown, .basic, .legacyPersonal:
            return false
        }
    }

    public var publishingRoute: PublishingRoute {
        hasCodeInjection ? .linkedLayer : .pasteCustomCSS
    }
}

/// How approved style changes reach the live site.
public enum PublishingRoute: String, Codable, Hashable, Sendable {
    /// A style sheet linked once from Code Injection; each publish is a GitHub commit.
    case linkedLayer
    /// The app copies the CSS and opens Squarespace's Custom CSS panel for you to paste it.
    case pasteCustomCSS

    public var title: String {
        switch self {
        case .linkedLayer: return "Linked style layer"
        case .pasteCustomCSS: return "Paste into Custom CSS"
        }
    }

    public var summary: String {
        switch self {
        case .linkedLayer:
            return "Your plan includes Code Injection. After a one-time setup, approved style changes go live from the app through a linked style sheet, and custom JavaScript can go live too."
        case .pasteCustomCSS:
            return "Your plan doesn't include Code Injection. When you publish, the app copies the CSS and opens Squarespace's Custom CSS panel for you to paste it. Custom JavaScript can't go live on this plan."
        }
    }
}
