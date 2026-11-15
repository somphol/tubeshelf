import XCTest
@testable import TubeShelfCore

final class LibraryTests: XCTestCase {
    private func makeVideo(
        id: String = "dQw4w9WgXcQ",
        title: String = "Sample",
        tags: [String] = ["Music"],
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Video {
        Video(youtubeID: id, title: title, channel: "Channel", tags: tags, addedAt: addedAt)
    }

    func testAddRejectsDuplicatesByYouTubeID() {
        var library = Library()
        XCTAssertTrue(library.add(makeVideo()))
        XCTAssertFalse(library.add(makeVideo(id: "dQw4w9WgXcQ", title: "Other")))
        XCTAssertEqual(library.count, 1)
    }

    func testTagCountsAndFilters() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", title: "A", tags: ["Cooking", "Design"]))
        library.add(makeVideo(id: "bbbbbbbbbbb", title: "B", tags: ["Design"]))
        library.add(makeVideo(id: "ccccccccccc", title: "C", tags: []))

        XCTAssertEqual(library.tagCounts.first?.name, "Design")
        XCTAssertEqual(library.tagCounts.first?.count, 2)
        XCTAssertEqual(library.unsortedCount, 1)
        XCTAssertEqual(library.videos(filter: .unsorted).count, 1)
        XCTAssertEqual(library.videos(filter: .tag("Cooking")).count, 1)
        XCTAssertEqual(library.videos(filter: .tag("cooking")).count, 1, "tag filter is case-insensitive")
        XCTAssertEqual(library.videos(filter: .all).count, 3)
    }

    func testNewestFirstOrdering() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", title: "Old", addedAt: Date(timeIntervalSince1970: 100)))
        library.add(makeVideo(id: "bbbbbbbbbbb", title: "New", addedAt: Date(timeIntervalSince1970: 900)))
        XCTAssertEqual(library.videos(filter: .all).map(\.title), ["New", "Old"])
    }

    func testSearchMatchesTitleChannelAndTags() {
        var library = Library()
        library.add(Video(youtubeID: "aaaaaaaaaaa", title: "Actors in Swift", channel: "Point-Free", tags: ["Programming"]))
        library.add(Video(youtubeID: "bbbbbbbbbbb", title: "Sourdough", channel: "Bake Club", tags: ["Cooking"]))

        XCTAssertEqual(library.videos(filter: .all, query: "swift").count, 1)
        XCTAssertEqual(library.videos(filter: .all, query: "bake club").count, 1)
        XCTAssertEqual(library.videos(filter: .all, query: "cooking").count, 1)
        XCTAssertEqual(library.videos(filter: .all, query: "swift sourdough").count, 0)
        XCTAssertEqual(library.videos(filter: .all, query: "").count, 2)
    }

    func testRenameTagMergesWithoutDuplicates() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: ["Cooking", "Design"]))
        library.add(makeVideo(id: "bbbbbbbbbbb", tags: ["Design"]))
        library.renameTag("Design", to: "Cooking")

        XCTAssertEqual(library.tagCounts.map(\.name), ["Cooking"])
        XCTAssertEqual(library.tagCounts.first?.count, 2)
        XCTAssertEqual(library.video(youtubeID: "aaaaaaaaaaa")?.tags, ["Cooking"])
    }

    func testDeleteTagRemovesFromEveryVideo() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: ["Cooking", "Design"]))
        library.deleteTag("design")
        XCTAssertEqual(library.video(youtubeID: "aaaaaaaaaaa")?.tags, ["Cooking"])
    }

    func testPlaylistFilterIsAViewModeNotAVideoFilter() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", title: "A"))
        XCTAssertTrue(library.videos(filter: .playlists).isEmpty)
        XCTAssertEqual(library.videos(filter: .all).count, 1)
    }

    func testWatchStatusFiltersAndCounts() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", title: "A"))
        library.add(makeVideo(id: "bbbbbbbbbbb", title: "B"))
        let first = library.videos[0].id
        library.setWatchStatus(.done, for: first)

        XCTAssertEqual(library.unwatchedCount, 1)
        XCTAssertEqual(library.videos(filter: .unwatched).map(\.title), ["B"])
        XCTAssertEqual(library.videos(filter: .all).count, 2)
    }

    func testOldVideosDecodeAsUnwatched() throws {
        let json = """
        {"videos":[{"youtubeID":"dQw4w9WgXcQ","title":"Old"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.videos[0].watchStatus, .unwatched)
    }

    func testCategoryThatMatchesAnAliasIsStoredAsTyped() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: []))
        let id = library.videos[0].id
        library.setTags(["Learning"], for: id)
        XCTAssertEqual(library.video(id: id)?.tags, ["Learning"])
        XCTAssertEqual(library.tagCounts.map(\.name), ["Learning"])
    }

    func testFavoritesFilter() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa"))
        library.add(makeVideo(id: "bbbbbbbbbbb"))
        let firstID = library.videos[0].id
        library.toggleFavorite(id: firstID)
        XCTAssertEqual(library.favoritesCount, 1)
        XCTAssertEqual(library.videos(filter: .favorites).first?.id, firstID)
    }

    func testVideoSetTagsNormalisesInput() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: []))
        let id = library.videos[0].id
        library.setTags(["design", "Design", "  #AI "], for: id)
        XCTAssertEqual(library.video(id: id)?.tags, ["Design", "AI"])
    }
}
