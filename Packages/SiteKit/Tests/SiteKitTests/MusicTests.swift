import Foundation
import XCTest
@testable import SiteKit

final class MusicCatalogTests: XCTestCase {
    /// Mirrors freemanedwards.com/music: source order differs from what visitors see.
    func items() -> [MusicPageItem] {
        [
            MusicPageItem(kind: .text, text: "Selected Compositions", y: 10, x: 40),
            MusicPageItem(kind: .text, text: "\u{00A0}2022", y: 60, x: 40),
            MusicPageItem(kind: .audio, text: "For Violin", subtitle: "Commissioned by Erik Carlson", durationMilliseconds: 107_000, y: 120, x: 40),
            MusicPageItem(kind: .audio, text: "2022 Work 25", subtitle: "", durationMilliseconds: 81_000, y: 200, x: 40),
            MusicPageItem(kind: .audio, text: "2022 Work 2", y: 280, x: 40),
            MusicPageItem(kind: .text, text: "2020", y: 400, x: 40),
            MusicPageItem(kind: .audio, text: "2020 Work 23", y: 460, x: 40),
            // Listed later in the source, but shown here on the page.
            MusicPageItem(kind: .audio, text: "2020 Work 21", y: 540, x: 40),
            MusicPageItem(kind: .text, text: "2018", y: 700, x: 40),
            MusicPageItem(kind: .audio, text: "Sine Wave and Colored Noise", y: 760, x: 40),
            MusicPageItem(kind: .audio, text: "2018 Work 13", y: 840, x: 40)
        ].reversed()
    }

    func testBuildsYearGroupsInVisualOrder() {
        let catalog = MusicCatalog.build(from: items())
        XCTAssertEqual(catalog.entries.map(\.title), [
            "For Violin", "2022 Work 25", "2022 Work 2", "2020 Work 23", "2020 Work 21",
            "Sine Wave and Colored Noise", "2018 Work 13"
        ])
        XCTAssertEqual(catalog.entries.map(\.year), [2022, 2022, 2022, 2020, 2020, 2018, 2018])
        XCTAssertEqual(catalog.years, [2022, 2020, 2018])
        XCTAssertEqual(catalog.entries.first?.subtitle, "Commissioned by Erik Carlson")
        XCTAssertNil(catalog.entries[1].subtitle)
        XCTAssertEqual(catalog.entries.first?.durationSeconds, 107)
    }

    func testParsesSourceHTML() {
        let html = """
        <div class="sqs-html-content" data-sqsp-text-block-content><p class="" style="white-space:pre-wrap;"><span>&nbsp;2022</span></p></div>
        <div class="sqs-audio-embed" data-design-style="minimal" data-show-download="false" data-asset-url="https://static1.squarespace.com/a/For+Violin+%282022%29.mp3" data-title="For Violin" data-author="Commissioned by Erik Carlson" data-length-in-milli-seconds="107000"> <!-- x --> </div>
        <div class="sqs-audio-embed" data-design-style="minimal" data-title="2022 Work 25" data-author="" data-length-in-milli-seconds="81000"></div>
        """
        let items = MusicCatalog.parseSourceOrder(html: html)
        XCTAssertEqual(items.map(\.kind), [.text, .audio, .audio])
        XCTAssertEqual(PieceTitle.yearHeading(items[0].text), 2022)
        XCTAssertEqual(items[1].text, "For Violin")
        XCTAssertEqual(items[1].subtitle, "Commissioned by Erik Carlson")
        XCTAssertEqual(items[1].durationMilliseconds, 107_000)
        XCTAssertEqual(items[2].designStyle, "minimal")
        let catalog = MusicCatalog.build(from: items)
        XCTAssertEqual(catalog.entries.map(\.year), [2022, 2022])
    }

    func testTitlesAndYears() {
        XCTAssertEqual(PieceTitle.title(fromFileName: "For Violin (2022).mp3"), "For Violin")
        XCTAssertEqual(PieceTitle.year(fromFileName: "For Violin (2022).mp3"), 2022)
        XCTAssertEqual(PieceTitle.year(fromFileName: "2023 Work 4.wav"), 2023)
        XCTAssertNil(PieceTitle.year(fromFileName: "Sine Wave and Colored Noise.wav"))
        XCTAssertEqual(PieceTitle.normalize("2022  Work-25"), "2022 work 25")
        XCTAssertEqual(PieceTitle.normalize("For Violin (2022)"), PieceTitle.normalize("for violin"))
        XCTAssertEqual(PieceTitle.workNumber("2019 Work 46"), 46)
        XCTAssertNil(PieceTitle.yearHeading("Selected Compositions"))
        XCTAssertTrue(PieceTitle.comesBefore("For Violin", "2022 Work 25"))
        XCTAssertTrue(PieceTitle.comesBefore("2022 Work 27", "2022 Work 25"))
        XCTAssertFalse(PieceTitle.comesBefore("2022 Work 3", "2022 Work 25"))
    }

    func testScansFolderAndCompares() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let year2024 = root.appendingPathComponent("2024", isDirectory: true)
        try FileManager.default.createDirectory(at: year2024, withIntermediateDirectories: true)
        let files = [
            root.appendingPathComponent("2022 Work 25.wav"),
            root.appendingPathComponent("2022 Work 25.mp3"),
            root.appendingPathComponent("2022 Work 27.wav"),
            root.appendingPathComponent("For Violin (2022).mp3"),
            year2024.appendingPathComponent("Untitled Study.aiff"),
            root.appendingPathComponent("notes.txt")
        ]
        for file in files { try Data("x".utf8).write(to: file) }

        let library = MusicLibraryScanner.scan(folder: root)
        XCTAssertEqual(Set(library.map(\.title)), ["2022 Work 25", "2022 Work 27", "For Violin", "Untitled Study"])
        let work25 = try XCTUnwrap(library.first { $0.title == "2022 Work 25" })
        XCTAssertEqual(work25.fileExtension, "mp3")
        XCTAssertEqual(work25.otherFormats, ["wav"])
        let study = try XCTUnwrap(library.first { $0.title == "Untitled Study" })
        XCTAssertEqual(study.year, 2024)
        XCTAssertEqual(study.yearSource, .folder)

        let catalog = MusicCatalog.build(from: items())
        let comparison = MusicComparison(library: library, catalog: catalog)
        XCTAssertEqual(Set(comparison.notOnSite.map(\.title)), ["2022 Work 27", "Untitled Study"])
        XCTAssertEqual(comparison.onSite.count, 7)
        XCTAssertEqual(comparison.onSite.first?.local?.title, "For Violin")
        XCTAssertEqual(comparison.siteOnly.count, 5)

        XCTAssertEqual(UploadPlan.plan(for: work25), .copy)
        let work27 = try XCTUnwrap(library.first { $0.title == "2022 Work 27" })
        XCTAssertEqual(UploadPlan.plan(for: work27), .convertToM4A)
        XCTAssertEqual(UploadPlan.fileName(for: work27), "2022 Work 27.m4a")
    }

    func testPlacementHints() {
        let catalog = MusicCatalog.build(from: items())
        XCTAssertEqual(Placement.hint(title: "2022 Work 27", year: 2022, catalog: catalog), "Under 2022, above \"2022 Work 25\"")
        XCTAssertEqual(Placement.hint(title: "2022 Work 1", year: 2022, catalog: catalog), "Under 2022, below \"2022 Work 2\"")
        XCTAssertEqual(Placement.hint(title: "2024 Work 1", year: 2024, catalog: catalog), "New 2024 heading at the top, above 2022")
        XCTAssertEqual(Placement.hint(title: "2019 Work 9", year: 2019, catalog: catalog), "New 2019 heading, above 2018")
        XCTAssertEqual(Placement.hint(title: "2015 Work 1", year: 2015, catalog: catalog), "New 2015 heading at the bottom, below 2018")
    }
}
