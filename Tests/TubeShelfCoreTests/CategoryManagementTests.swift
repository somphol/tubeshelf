import XCTest
@testable import TubeShelfCore

final class CategoryManagementTests: XCTestCase {
    private func makeVideo(
        id: String,
        tags: [String],
        title: String = "Video",
        addedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Video {
        Video(youtubeID: id, title: title, channel: "Channel", tags: tags, addedAt: addedAt)
    }

    private func library() -> Library {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: ["Cooking", "Travel"], title: "Sourdough in Tokyo"))
        library.add(makeVideo(id: "bbbbbbbbbbb", tags: ["Cooking"], title: "Bread part two"))
        library.add(makeVideo(id: "ccccccccccc", tags: ["Design"], title: "Grids and type"))
        return library
    }

    func testPinningPreservesOrderAndDeduplicates() {
        var shelf = library()
        XCTAssertTrue(shelf.togglePin("Design"))
        XCTAssertTrue(shelf.togglePin("Cooking"))
        shelf.pin("Cooking") // already pinned: ignored, order kept
        XCTAssertEqual(shelf.pinnedTagCounts.map(\.name), ["Design", "Cooking"])
        XCTAssertTrue(shelf.isPinned("cooking"))
        XCTAssertEqual(shelf.pinnedTagCounts.last?.count, 2)

        XCTAssertFalse(shelf.togglePin("Cooking"))
        XCTAssertEqual(shelf.pinnedTagCounts.map(\.name), ["Design"])
    }

    func testPinnedCategoriesLeaveTheMainList() {
        var shelf = library()
        shelf.pin("Cooking")
        XCTAssertEqual(shelf.pinnedTagCounts.map(\.name), ["Cooking"])
        XCTAssertEqual(shelf.unpinnedTagCounts(sortedBy: .mostVideos).map(\.name), ["Design", "Travel"])
    }

    func testSortingByCountAndNameInBothDirections() {
        let shelf = library()
        XCTAssertEqual(shelf.tagCounts(sortedBy: .mostVideos).map(\.name), ["Cooking", "Design", "Travel"])
        XCTAssertEqual(shelf.tagCounts(sortedBy: .mostVideos, ascending: true).map(\.name), ["Design", "Travel", "Cooking"])
        XCTAssertEqual(shelf.tagCounts(sortedBy: .name, ascending: true).map(\.name), ["Cooking", "Design", "Travel"])
        XCTAssertEqual(shelf.tagCounts(sortedBy: .name, ascending: false).map(\.name), ["Travel", "Design", "Cooking"])
    }

    func testMergeMovesVideosAndRemovesTheSource() {
        var shelf = library()
        let moved = shelf.mergeTags("Travel", into: "Cooking")
        XCTAssertEqual(moved, 1)
        XCTAssertEqual(shelf.tagCounts.map(\.name), ["Cooking", "Design"])
        XCTAssertEqual(shelf.video(youtubeID: "aaaaaaaaaaa")?.tags, ["Cooking"])
        XCTAssertEqual(shelf.videos(filter: .tag("Travel")).count, 0)
        XCTAssertEqual(shelf.videos(filter: .tag("Cooking")).count, 2)
    }

    func testMergeIntoAnExistingTagDoesNotDuplicate() {
        var shelf = library()
        shelf.mergeTags("Travel", into: "Cooking")
        shelf.mergeTags("Cooking", into: "Cooking")
        XCTAssertEqual(shelf.video(youtubeID: "aaaaaaaaaaa")?.tags, ["Cooking"])
        XCTAssertEqual(shelf.video(youtubeID: "aaaaaaaaaaa")?.tags.count, 1)
    }

    func testMergeTransfersThePin() {
        var shelf = library()
        shelf.pin("Travel")
        shelf.mergeTags("Travel", into: "Cooking")
        XCTAssertTrue(shelf.isPinned("Cooking"))
        XCTAssertFalse(shelf.isPinned("Travel"))
        XCTAssertEqual(shelf.pinnedTagCounts.map(\.name), ["Cooking"])
    }

    func testRenameKeepsThePinAndDeleteDropsIt() {
        var shelf = library()
        shelf.pin("Design")
        shelf.renameTag("Design", to: "Graphic Design")
        XCTAssertTrue(shelf.isPinned("Graphic Design"))
        XCTAssertFalse(shelf.isPinned("Design"))

        shelf.deleteTag("Graphic Design")
        XCTAssertFalse(shelf.isPinned("Graphic Design"))
        XCTAssertTrue(shelf.pinnedTagCounts.isEmpty)
    }

    func testPinsSurviveDiskRoundTripAndOldFilesDecode() throws {
        var shelf = library()
        shelf.pin("Cooking")

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-pin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        try store.save(shelf)
        XCTAssertEqual(try store.load(), shelf)
        XCTAssertEqual(try store.load().pinnedTags, ["Cooking"])

        let legacy = """
        {"videos":[{"youtubeID":"dQw4w9WgXcQ","title":"Old"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(Library.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.pinnedTags, [])
    }

    func testPinsArePrunedExplicitlyNotOnDecode() throws {
        // Decoding must not prune: the app adds playlist categories after loading,
        // so a course-only pin has to survive until the app can judge it.
        let json = """
        {"videos":[],"pinnedTags":["Cooking","Travel"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var library = try decoder.decode(Library.self, from: Data(json.utf8))
        XCTAssertEqual(library.pinnedTags, ["Cooking", "Travel"])

        library.prunePinnedTags()
        XCTAssertEqual(library.pinnedTags, [])
    }

    func testPinsCanBeRetainedAgainstAnExternalCategoryList() {
        var library = Library()
        library.add(makeVideo(id: "aaaaaaaaaaa", tags: ["Cooking"]))
        library.pin("Cooking")
        library.pin("C++")

        library.retainPins(among: ["cooking", "c++"])
        XCTAssertEqual(library.pinnedTags, ["Cooking", "C++"])
    }

    func testChannelPinsRoundTripAndPrune() throws {
        var shelf = Library()
        shelf.add(Video(youtubeID: "aaaaaaaaaaa", title: "Lecture", channel: "Stanford Online"))
        shelf.add(Video(youtubeID: "bbbbbbbbbbb", title: "Vectors", channel: "3Blue1Brown"))

        XCTAssertTrue(shelf.toggleChannelPin("stanford online"))
        XCTAssertEqual(shelf.pinnedChannels, ["stanford online"], "first spelling wins")
        XCTAssertEqual(shelf.pinnedChannelCounts.map(\.name), ["Stanford Online"], "display uses the video spelling")
        XCTAssertTrue(shelf.isChannelPinned("STANFORD ONLINE"))

        shelf.pinChannel("3Blue1Brown")
        shelf.pinChannel("3blue1brown")
        XCTAssertEqual(shelf.pinnedChannels, ["stanford online", "3Blue1Brown"])

        shelf.retainChannelPins(among: ["3blue1brown"])
        XCTAssertEqual(shelf.pinnedChannels, ["3Blue1Brown"])

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-channel-pin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory)
        try store.save(shelf)
        XCTAssertEqual(try store.load().pinnedChannels, ["3Blue1Brown"])

        let legacy = #"{"videos":[]}"#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(Library.self, from: Data(legacy.utf8)).pinnedChannels, [])
    }

    func testTitleOnlySearchIgnoresCategoriesAndNotes() {
        var shelf = Library()
        shelf.add(Video(
            youtubeID: "aaaaaaaaaaa",
            title: "Actors in Swift",
            channel: "Point-Free",
            tags: ["Programming"],
            note: "watch the concurrency part"
        ))
        shelf.add(Video(
            youtubeID: "bbbbbbbbbbb",
            title: "Sourdough",
            channel: "Bake Club",
            tags: ["Cooking"],
            note: "swift crumb"
        ))

        XCTAssertEqual(shelf.videos(filter: .all, query: "swift", scope: .titles).count, 1)
        XCTAssertEqual(shelf.videos(filter: .all, query: "swift").count, 2)
        XCTAssertEqual(shelf.videos(filter: .all, query: "programming", scope: .titles).count, 0)
        XCTAssertEqual(shelf.videos(filter: .all, query: "programming").count, 1)
    }
}


final class ChannelFacetTests: XCTestCase {
    private func shelf() -> Library {
        var library = Library()
        // Three videos from one channel, two of them Programming and one Design:
        // 2/3 is enough for an affinity, 60% share required.
        library.add(Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "Fireship",
                          tags: ["Programming"], addedAt: Date(timeIntervalSince1970: 100)))
        library.add(Video(youtubeID: "bbbbbbbbbbb", title: "B", channel: "fireship",
                          tags: ["Programming"], addedAt: Date(timeIntervalSince1970: 200)))
        library.add(Video(youtubeID: "ccccccccccc", title: "C", channel: "Fireship",
                          tags: ["Design"], addedAt: Date(timeIntervalSince1970: 300)))
        library.add(Video(youtubeID: "ddddddddddd", title: "D", channel: "Cook Club",
                          tags: ["Cooking"], addedAt: Date(timeIntervalSince1970: 400)))
        library.add(Video(youtubeID: "eeeeeeeeeee", title: "E", channel: "Cook Club",
                          tags: [], addedAt: Date(timeIntervalSince1970: 500)))
        return library
    }

    func testChannelCountsMergeSpellingAndSortBySize() {
        let library = shelf()
        let counts = library.channelCounts()
        XCTAssertEqual(counts.first?.name, "Fireship")
        XCTAssertEqual(counts.first?.count, 3)
        XCTAssertEqual(counts.count, 2)
        XCTAssertEqual(library.channelCounts(sortedBy: .name, ascending: true).map(\.name), ["Cook Club", "Fireship"])
    }

    func testChannelFilterIsCaseInsensitive() {
        let library = shelf()
        XCTAssertEqual(library.videos(filter: .channel("Fireship")).count, 3)
        XCTAssertEqual(library.videos(filter: .channel("fireship")).count, 3)
        XCTAssertEqual(library.videos(filter: .channel("Nobody")).count, 0)
    }

    func testAffinityNeedsEnoughVideosAndASharedCategory() {
        let library = shelf()
        XCTAssertEqual(library.channelAffinity(for: "Fireship"), "Programming")
        // Only two videos: below the three-video minimum.
        XCTAssertNil(library.channelAffinity(for: "Cook Club"))
    }

    func testAffinityIsNilWhenTheChannelIsSplit() {
        var library = Library()
        library.add(Video(youtubeID: "aaaaaaaaaaa", title: "A", channel: "Split", tags: ["Cooking"]))
        library.add(Video(youtubeID: "bbbbbbbbbbb", title: "B", channel: "Split", tags: ["Travel"]))
        library.add(Video(youtubeID: "ccccccccccc", title: "C", channel: "Split", tags: ["Design"]))
        XCTAssertNil(library.channelAffinity(for: "Split"))
    }

    func testChannelHintOnlyFillsAnEmptyAnswer() async {
        let hinted = await TagEngine().suggest(
            title: "Untitled conversation",
            channel: "Some Channel",
            channelHint: "Cooking"
        )
        XCTAssertEqual(hinted.tags, ["Cooking"])

        let decisive = await TagEngine().suggest(
            title: "Sourdough bread for beginners",
            channel: "Some Channel",
            channelHint: "Cooking"
        )
        XCTAssertTrue(decisive.tags.contains("Cooking"))
    }

    func testChannelHintIgnoresUnknownCategories() async {
        let suggestion = await TagEngine().suggest(
            title: "Untitled",
            channel: "Some Channel",
            channelHint: "Made Up Category"
        )
        XCTAssertTrue(suggestion.tags.isEmpty)
    }
}
