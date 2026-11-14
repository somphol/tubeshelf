import XCTest
@testable import TubeShelfCore

final class StoreAndDeckTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testRoundTripThroughDisk() throws {
        let store = LibraryStore(directory: temporaryDirectory)
        var library = Library()
        library.add(Video(
            youtubeID: "dQw4w9WgXcQ",
            title: "Never Gonna Give You Up",
            channel: "Rick Astley",
            tags: ["Music"],
            note: "the one with the rickroll",
            durationSeconds: 213,
            isFavorite: true
        ))
        try store.save(library)

        let reloaded = try store.load()
        XCTAssertEqual(reloaded, library)
        XCTAssertEqual(reloaded.videos.first?.durationSeconds, 213)
        XCTAssertTrue(reloaded.videos.first?.isFavorite == true)
    }

    func testMissingFileLoadsEmpty() throws {
        let store = LibraryStore(directory: temporaryDirectory)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testCorruptFileIsQuarantinedNotCrashed() throws {
        let store = LibraryStore(directory: temporaryDirectory)
        try Data("not json".utf8).write(to: store.fileURL)

        let recovered = try store.load()
        XCTAssertTrue(recovered.isEmpty, "a corrupt file should yield an empty shelf")

        let files = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectory.path)
        XCTAssertTrue(
            files.contains { $0.hasPrefix("library-corrupt-") },
            "the broken file should be moved aside, found: \(files)"
        )
    }

    func testDeckNavigationAndClamping() {
        let videos = (0..<3).map {
            Video(youtubeID: String(repeating: "a", count: 11), title: "V\($0)", channel: "C")
        }
        var deck = DeckModel(slides: videos, startAt: videos[1].id)
        XCTAssertEqual(deck.position, 2)
        XCTAssertEqual(deck.current?.title, "V1")

        XCTAssertTrue(deck.showNext())
        XCTAssertTrue(deck.isLast)
        XCTAssertFalse(deck.showNext())
        XCTAssertEqual(deck.position, 3)

        XCTAssertTrue(deck.showPrevious())
        XCTAssertTrue(deck.showPrevious())
        XCTAssertFalse(deck.showPrevious())
        XCTAssertTrue(deck.isFirst)
    }

    func testDeckStartsAtZeroForUnknownOrEmptyInput() {
        XCTAssertEqual(DeckModel(slides: []).position, 0)
        XCTAssertNil(DeckModel(slides: []).current)
        let videos = [Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C")]
        XCTAssertEqual(DeckModel(slides: videos, startAt: UUID()).position, 1)
    }

    func testDeckRefreshKeepsCurrentVideoSelected() {
        let first = Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C")
        let second = Video(youtubeID: "bbbbbbbbbbb", title: "B", channel: "C")
        var deck = DeckModel(slides: [first, second], startAt: second.id)
        deck.refresh(with: [second])
        XCTAssertEqual(deck.current?.id, second.id)
        XCTAssertEqual(deck.position, 1)
    }

    func testMetadataScrapingIsForgiving() {
        let html = """
        <html><head><meta name="description" content="A &amp; B"></head>
        <body>{"shortDescription":"Line one\\nLine two","lengthSeconds":"754"}</body></html>
        """
        XCTAssertEqual(MetaScraper.description(fromHTML: html), "Line one\nLine two")
        XCTAssertEqual(MetaScraper.durationSeconds(fromHTML: html), 754)
        XCTAssertNil(MetaScraper.durationSeconds(fromHTML: "<html></html>"))
    }

    func testOEmbedPayloadDecodes() throws {
        let json = """
        {"title":"Never Gonna Give You Up","author_name":"Rick Astley","thumbnail_url":"https://i.ytimg.com/vi/x/hq.jpg"}
        """
        let payload = try JSONDecoder().decode(OEmbedPayload.self, from: Data(json.utf8))
        XCTAssertEqual(payload.title, "Never Gonna Give You Up")
        XCTAssertEqual(payload.author_name, "Rick Astley")
    }

    func testOldLibraryFilesStillDecode() throws {
        let json = """
        {"videos":[{"youtubeID":"dQw4w9WgXcQ","title":"Old"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.count, 1)
        XCTAssertEqual(library.videos[0].channel, "")
        XCTAssertFalse(library.videos[0].isFavorite)
    }
}
