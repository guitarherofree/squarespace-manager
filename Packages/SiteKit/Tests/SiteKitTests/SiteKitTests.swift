import Foundation
import XCTest
@testable import SiteKit

/// Serves canned responses keyed by absolute URL; anything else is a 404.
struct StubClient: HTTPClient {
    let routes: [String: (Int, String)]

    func get(_ url: URL) async throws -> HTTPResponse {
        if let route = routes[url.absoluteString] {
            return HTTPResponse(url: url, status: route.0, data: Data(route.1.utf8), contentType: nil)
        }
        return HTTPResponse(url: url, status: 404, data: Data(), contentType: nil)
    }
}

final class DetectionTests: XCTestCase {
    func testReadsVersion71FromContext() {
        let html = """
        <html><head><title>Freeman</title>
        <script>Static.SQUARESPACE_CONTEXT = {"templateVersion":"7.1","templateId":"abc123","website":{"id":"w1","siteTitle":"Freeman {Edwards}","baseUrl":"https://www.example.com"},"note":"a \\" } b"};</script>
        </head><body></body></html>
        """
        let info = SiteDetector.analyze(html: html, now: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(info.isSquarespace)
        XCTAssertEqual(info.version, .v71)
        XCTAssertEqual(info.versionConfidence, .confirmed)
        XCTAssertEqual(info.templateID, "abc123")
        XCTAssertEqual(info.siteTitle, "Freeman {Edwards}")
        XCTAssertEqual(info.websiteID, "w1")
    }

    func testReadsVersion70FromContext() {
        let html = #"<script>Static.SQUARESPACE_CONTEXT={"templateVersion":"7","website":{}};</script>"#
        let info = SiteDetector.analyze(html: html)
        XCTAssertEqual(info.version, .v70)
        XCTAssertEqual(info.versionConfidence, .confirmed)
    }

    func testFallsBackToMarkupMarkers() {
        let html = #"<link href="https://static1.squarespace.com/static/x.css"><div class="fe-block"></div>"#
        let info = SiteDetector.analyze(html: html)
        XCTAssertTrue(info.isSquarespace)
        XCTAssertEqual(info.version, .v71)
        XCTAssertEqual(info.versionConfidence, .likely)
    }

    func testNonSquarespacePage() {
        let info = SiteDetector.analyze(html: "<html><body>Hello</body></html>")
        XCTAssertFalse(info.isSquarespace)
        XCTAssertEqual(info.version, .unknown)
    }
}

final class AddressAndPathTests: XCTestCase {
    func testNormalizesTypedAddresses() {
        XCTAssertEqual(SiteAddress.normalize("freemanedwards.com")?.absoluteString, "https://freemanedwards.com/")
        XCTAssertEqual(SiteAddress.normalize(" http://WWW.Example.com/about?x=1 ")?.absoluteString, "https://www.example.com/")
        XCTAssertNil(SiteAddress.normalize("not a site"))
        XCTAssertNil(SiteAddress.normalize(""))
    }

    func testSlugs() {
        XCTAssertEqual(PagePaths.slug(for: URL(string: "https://x.com/")!), "home")
        XCTAssertEqual(PagePaths.slug(for: URL(string: "https://x.com")!), "home")
        XCTAssertEqual(PagePaths.slug(for: URL(string: "https://x.com/About-Me")!), "about-me")
        XCTAssertEqual(PagePaths.slug(for: URL(string: "https://x.com/blog/post-1?x=2")!), "blog__post-1")
        var used: Set<String> = ["about"]
        XCTAssertEqual(PagePaths.uniqueSlug(for: URL(string: "https://x.com/about")!, used: &used), "about-2")
    }

    func testJSONURL() {
        XCTAssertEqual(PagePaths.jsonURL(for: URL(string: "https://x.com/")!).absoluteString, "https://x.com/?format=json-pretty")
        XCTAssertEqual(PagePaths.jsonURL(for: URL(string: "https://x.com/shop?category=a")!).absoluteString,
                       "https://x.com/shop?category=a&format=json-pretty")
    }

    func testSitemap() {
        let xml = """
        <urlset><url><loc>https://www.x.com/</loc><image:image><image:loc>https://img.x.com/a.jpg</image:loc></image:image></url>
        <url><loc> https://www.x.com/a?b=1&amp;c=2 </loc></url></urlset>
        """
        let sitemap = Sitemap.parse(xml)
        XCTAssertFalse(sitemap.isIndex)
        XCTAssertEqual(sitemap.locations.map(\.absoluteString), ["https://www.x.com/", "https://www.x.com/a?b=1&c=2"])
        XCTAssertTrue(Sitemap.parse("<sitemapindex><sitemap><loc>https://x.com/s.xml</loc></sitemap></sitemapindex>").isIndex)
    }

    func testTitle() {
        XCTAssertEqual(HTMLText.title(in: "<head><title> About &amp; Contact </title></head>"), "About & Contact")
    }
}

final class NormalizerTests: XCTestCase {
    func testContentHashIgnoresVolatileKeysAndOrder() {
        let a = Data(#"{"collection":{"title":"Home"},"now":1}"#.utf8)
        let b = Data(#"{"now":2,"collection":{"title":"Home"}}"#.utf8)
        let c = Data(#"{"collection":{"title":"Home page"}}"#.utf8)
        XCTAssertEqual(ContentNormalizer.contentHash(a), ContentNormalizer.contentHash(b))
        XCTAssertNotEqual(ContentNormalizer.contentHash(a), ContentNormalizer.contentHash(c))
        XCTAssertNil(ContentNormalizer.contentHash(Data("<html>".utf8)))
    }

    func testMarkupHashIgnoresScripts() {
        let a = "<p>Hi</p><script nonce=\"1\">var t = 1;</script>"
        let b = "<p>Hi</p>\n<script nonce=\"2\">var t = 2;</script>"
        XCTAssertEqual(ContentNormalizer.markupHash(a), ContentNormalizer.markupHash(b))
    }

    func testSHA256() {
        XCTAssertEqual(Hashing.sha256Hex("abc"), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testRedaction() {
        let text = "token=ghp_abcdefghijklmnopqrstuvwxyz0123 Authorization: Bearer abc.def key sk-ant-api03-secretvalue"
        let redacted = Redactor.redact(text)
        XCTAssertFalse(redacted.contains("ghp_abcdefghijklmnopqrstuvwxyz0123"))
        XCTAssertFalse(redacted.contains("abc.def"))
        XCTAssertFalse(redacted.contains("secretvalue"))
    }
}

final class PlanTests: XCTestCase {
    func testRoutes() {
        XCTAssertEqual(SquarespacePlan.legacyPersonal.publishingRoute, .pasteCustomCSS)
        XCTAssertEqual(SquarespacePlan.basic.publishingRoute, .pasteCustomCSS)
        XCTAssertEqual(SquarespacePlan.unknown.publishingRoute, .pasteCustomCSS)
        XCTAssertEqual(SquarespacePlan.core.publishingRoute, .linkedLayer)
        XCTAssertEqual(SquarespacePlan.legacyBusiness.publishingRoute, .linkedLayer)
    }
}

final class SnapshotTests: XCTestCase {
    private func makeRoutes(aboutTitle: String) -> [String: (Int, String)] {
        let home = #"<html><head><title>Home</title><script>Static.SQUARESPACE_CONTEXT = {"templateVersion":"7.1","website":{"siteTitle":"Example"}};</script></head><body>Hi</body></html>"#
        let sitemap = """
        <urlset><url><loc>https://example.com/</loc></url><url><loc>https://example.com/about</loc></url>
        <url><loc>https://other.com/elsewhere</loc></url></urlset>
        """
        return [
            "https://example.com/": (200, home),
            "https://example.com/sitemap.xml": (200, sitemap),
            "https://example.com/?format=json-pretty": (200, #"{"collection":{"title":"Home"},"now":1}"#),
            "https://example.com/about": (200, "<html><head><title>About</title></head><body>About</body></html>"),
            "https://example.com/about?format=json-pretty": (200, "{\"collection\":{\"title\":\"\(aboutTitle)\"}}"),
            "https://example.com/site.css?minify=false": (200, "body { color: black; }")
        ]
    }

    func testSnapshotAndDiff() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SnapshotStore(root: root)

        let first = SnapshotService(client: StubClient(routes: makeRoutes(aboutTitle: "About")), store: store, requestDelay: 0)
        let one = try await first.takeSnapshot(siteURL: URL(string: "https://example.com")!, now: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(one.pages.map(\.url), ["https://example.com/", "https://example.com/about"])
        XCTAssertEqual(one.siteInfo.version, .v71)
        XCTAssertNotNil(one.cssHash)
        XCTAssertEqual(one.pages.last?.title, "About")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.directory(for: one.id).appendingPathComponent("pages/about.json").path))

        let second = SnapshotService(client: StubClient(routes: makeRoutes(aboutTitle: "About me")), store: store, requestDelay: 0)
        let two = try await second.takeSnapshot(siteURL: URL(string: "https://example.com/")!, now: Date(timeIntervalSince1970: 2_000))

        let listed = try store.list()
        XCTAssertEqual(listed.map(\.id), [two.id, one.id])

        let diff = SnapshotDiff.compare(old: one, new: two)
        XCTAssertFalse(diff.isBaseline)
        XCTAssertFalse(diff.cssChanged)
        XCTAssertEqual(diff.changedEntries.map(\.url), ["https://example.com/about"])
        XCTAssertEqual(diff.changedEntries.first?.kind, .contentChanged)

        let baseline = SnapshotDiff.compare(old: nil, new: one)
        XCTAssertTrue(baseline.isBaseline)
    }
}
