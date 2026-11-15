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
        XCTAssertEqual(DeckModel(slides: [DeckSlide]()).position, 0)
        XCTAssertNil(DeckModel(slides: [DeckSlide]()).current)
        let videos = [Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C")]
        XCTAssertEqual(DeckModel(slides: videos, startAt: UUID()).position, 1)
    }

    func testDeckRefreshKeepsCurrentVideoSelected() {
        let first = Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "C")
        let second = Video(youtubeID: "bbbbbbbbbbb", title: "B", channel: "C")
        var deck = DeckModel(slides: [first, second], startAt: second.id)
        deck.refresh(with: [second])
        XCTAssertEqual(deck.current?.video?.id, second.id)
        XCTAssertEqual(deck.position, 1)
    }

    func testBackupKeepsTheExactSavedMoment() throws {
        let zone = TimeZone(identifier: "Asia/Bangkok")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let moment = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14, hour: 19, minute: 32, second: 26
        ))!

        var library = Library()
        library.add(Video(youtubeID: "dQw4w9WgXcQ", title: "Saved abroad", channel: "C", addedAt: moment))

        let restored = try ShelfBackup.decode(try ShelfBackup.encode(library))
        XCTAssertEqual(
            restored.videos[0].addedAt.timeIntervalSince1970,
            moment.timeIntervalSince1970,
            accuracy: 0.001,
            "import must honour the original moment, to the second"
        )
        XCTAssertTrue(restored.videos[0].addedTimestamp(timeZone: zone).contains("19:32"))
    }

    func testTimestampLabelCarriesDateTimeAndZone() {
        let zone = TimeZone(identifier: "Asia/Bangkok")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let moment = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14, hour: 9, minute: 5, second: 0
        ))!
        let video = Video(youtubeID: "dQw4w9WgXcQ", title: "x", channel: "c", addedAt: moment)

        let label = video.addedTimestamp(timeZone: zone)
        XCTAssertTrue(label.contains("14 Nov 2026"), label)
        XCTAssertTrue(label.contains("09:05"), label)
        let expectedZone = zone.abbreviation(for: moment) ?? "GMT+7"
        XCTAssertTrue(label.contains(expectedZone), "\(label) should mention \(expectedZone)")
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

    func testMetadataScrapingFallsBackForEmbedDisabledVideos() {
        let html = """
        <html><head><meta property="og:title" content="Stanford CS229 I Machine Learning &amp; LLMs"></head>
        <body>{"playableInEmbed":false,"ownerChannelName":"Stanford Online","lengthSeconds":"6271"}</body></html>
        """
        XCTAssertEqual(MetaScraper.title(fromHTML: html), "Stanford CS229 I Machine Learning & LLMs")
        XCTAssertEqual(MetaScraper.channel(fromHTML: html), "Stanford Online")
        XCTAssertNil(MetaScraper.title(fromHTML: "<html></html>"))
        XCTAssertNil(MetaScraper.channel(fromHTML: "<html></html>"))
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


final class DeckSlideTests: XCTestCase {
    private func video(_ id: String, _ title: String) -> Video {
        Video(youtubeID: id, title: title, channel: "C")
    }

    private func course() -> PlaylistRecord {
        PlaylistRecord(
            id: "PLZHQObOWTQDPD3MizzM2xVFitgF8hE_ab",
            title: "Essence of linear algebra",
            channel: "3Blue1Brown",
            items: (0..<3).map {
                PlaylistItem(videoID: String(format: "vid%08d", $0), title: "Chapter \($0)", channel: "3Blue1Brown", durationSeconds: 600)
            }
        )
    }

    func testADeckCanHoldVideosAndCourses() {
        let first = video("aaaaaaaaaaa", "First")
        let record = course()
        var deck = DeckModel(
            slides: [.video(first), .playlist(record)],
            startAt: "p-\(record.id)"
        )

        XCTAssertEqual(deck.position, 2)
        XCTAssertEqual(deck.current?.playlist?.title, "Essence of linear algebra")
        XCTAssertNil(deck.current?.video)
        XCTAssertEqual(deck.current?.thumbnailVideoID, "vid00000000")

        XCTAssertTrue(deck.showPrevious())
        XCTAssertEqual(deck.current?.video?.id, first.id)
        XCTAssertFalse(deck.showPrevious())
    }

    func testRefreshKeepsTheCurrentCourseSelected() {
        let record = course()
        var deck = DeckModel(slides: [.playlist(record)], startAt: "p-\(record.id)")
        deck.refresh(with: [.playlist(record), .video(video("bbbbbbbbbbb", "New"))])
        XCTAssertEqual(deck.current?.playlist?.id, record.id)
        XCTAssertEqual(deck.total, 2)
    }

    func testVideoOnlyDecksStillWork() {
        let first = video("aaaaaaaaaaa", "First")
        let second = video("bbbbbbbbbbb", "Second")
        let deck = DeckModel(slides: [first, second], startAt: second.id)
        XCTAssertEqual(deck.current?.video?.id, second.id)
        XCTAssertEqual(deck.total, 2)
    }
}
