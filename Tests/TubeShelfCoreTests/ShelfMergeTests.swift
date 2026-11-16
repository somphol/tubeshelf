import XCTest
@testable import TubeShelfCore

final class ShelfMergeTests: XCTestCase {
    private func video(
        _ youtubeID: String,
        note: String = "",
        tags: [String] = [],
        favorite: Bool = false,
        status: WatchStatus = .unwatched,
        title: String? = nil
    ) -> Video {
        Video(
            youtubeID: youtubeID,
            title: title ?? youtubeID,
            channel: "Channel",
            tags: tags,
            note: note,
            isFavorite: favorite,
            watchStatus: status
        )
    }

    private func snapshot(
        _ videos: [Video],
        playlists: [PlaylistRecord] = [],
        tags: [String] = [],
        channels: [String] = []
    ) -> ShelfSnapshot {
        ShelfSnapshot(
            library: Library(videos: videos, pinnedTags: tags, pinnedChannels: channels),
            playlists: playlists
        )
    }

    func testOneSidedFieldsMergeWithoutConflict() {
        let base = snapshot([video("a", note: "old")])
        let mine = snapshot([video("a", note: "mac")])
        let theirs = snapshot([video("a", note: "old", favorite: true)])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.snapshot.library.videos[0].note, "mac")
        XCTAssertTrue(result.snapshot.library.videos[0].isFavorite)
        XCTAssertEqual(result.stats.updated, 1)
    }

    func testBothNotesConflictAndResolveToBackup() {
        let base = snapshot([video("a", note: "old")])
        let mine = snapshot([video("a", note: "mac")])
        let theirs = snapshot([video("a", note: "web")])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.conflicts.count, 1)
        let conflict = result.conflicts[0]
        XCTAssertEqual(conflict.fields.first?.field, .note)
        XCTAssertEqual(result.snapshot.library.videos[0].note, "mac")

        let resolved = ShelfMerger.resolve(result, choices: [
            conflict.choiceKey(for: conflict.fields[0]): .theirs
        ])
        XCTAssertEqual(resolved.library.videos[0].note, "web")
    }

    func testTagsMergeAsSetsAndKeepRemovals() {
        let base = snapshot([video("a", tags: ["Math"])])
        let mine = snapshot([video("a", tags: ["Calculus"])])
        let theirs = snapshot([video("a", tags: ["Math", "Physics"])])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.snapshot.library.videos[0].tags, ["Calculus", "Physics"])
        if case .tags(let both)? = result.conflicts[0].fields.first?.both {
            XCTAssertEqual(both, ["Calculus", "Physics"])
        } else {
            XCTFail("expected a combined tag set")
        }
    }

    func testWatchStatusConflictResolvesIndependently() {
        let base = snapshot([video("a", status: .unwatched)])
        let mine = snapshot([video("a", favorite: true, status: .watching)])
        let theirs = snapshot([video("a", status: .done)])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertTrue(result.snapshot.library.videos[0].isFavorite)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].fields.map(\.field), [.watchStatus])

        let resolved = ShelfMerger.resolve(result, choices: [
            result.conflicts[0].choiceKey(for: result.conflicts[0].fields[0]): .theirs
        ])
        XCTAssertEqual(resolved.library.videos[0].watchStatus, .done)
        XCTAssertTrue(resolved.library.videos[0].isFavorite)
    }

    func testVideosAddedOnEitherSideAreKept() {
        let base = snapshot([video("a")])
        let mine = snapshot([video("a"), video("local")])
        let theirs = snapshot([video("a"), video("web")])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.snapshot.library.videos.map(\.youtubeID), ["a", "local", "web"])
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.stats.added, 1)
        XCTAssertEqual(result.stats.kept, 1)
    }

    func testBackupDeletionAppliesWhenTheMacDidNotEdit() {
        let base = snapshot([video("a"), video("b")])
        let mine = snapshot([video("a", note: "edited"), video("b")])
        let theirs = snapshot([video("a")])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.snapshot.library.videos.map(\.youtubeID), ["a"])
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.stats.deleted, 1)
    }

    func testLocallyEditedVideoDeletedInBackupAsks() {
        let base = snapshot([video("a")])
        let mine = snapshot([video("a", note: "edited")])
        let theirs = snapshot([])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.conflicts.count, 1)
        XCTAssertEqual(result.conflicts[0].presence, .deletedInBackup)
        XCTAssertEqual(result.snapshot.library.videos.count, 1)

        let resolved = ShelfMerger.resolve(result, choices: [
            result.conflicts[0].presenceKey: .theirs
        ])
        XCTAssertTrue(resolved.library.videos.isEmpty)
    }

    func testVideoDeletedHereButEditedInBackupCanReturn() {
        let base = snapshot([video("a")])
        let mine = snapshot([])
        let theirs = snapshot([video("a", note: "edited")])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertTrue(result.snapshot.library.videos.isEmpty)
        XCTAssertEqual(result.conflicts[0].presence, .deletedHere)

        let resolved = ShelfMerger.resolve(result, choices: [
            result.conflicts[0].presenceKey: .theirs
        ])
        XCTAssertEqual(resolved.library.videos.first?.note, "edited")
    }

    func testWithoutABaseKeepsCurrentOnlyVideosAndAddsIncoming() {
        let mine = snapshot([video("a", note: "kept")])
        let theirs = snapshot([video("b")])

        let result = ShelfMerger.merge(base: nil, mine: mine, theirs: theirs)
        XCTAssertEqual(result.snapshot.library.videos.map(\.youtubeID), ["a", "b"])
        XCTAssertEqual(result.snapshot.library.videos[0].note, "kept")
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(result.stats.kept, 1)
        XCTAssertEqual(result.stats.added, 1)
    }

    func testWithoutABaseDifferencesBecomeConflicts() {
        let mine = snapshot([video("a", note: "mac", tags: ["Math"])])
        let theirs = snapshot([video("a", note: "web", tags: ["Calculus"])])

        let result = ShelfMerger.merge(base: nil, mine: mine, theirs: theirs)
        XCTAssertEqual(result.conflicts[0].fields.map(\.field), [.tags, .note])
        XCTAssertEqual(Set(result.snapshot.library.videos[0].tags), Set(["Math", "Calculus"]))
        XCTAssertEqual(result.snapshot.library.videos[0].note, "mac")
    }

    func testPinsMergeThreeWays() {
        let base = snapshot([], tags: ["Math", "Old"], channels: ["A"])
        let mine = snapshot([], tags: ["Math", "Cooking"], channels: ["A", "B"])
        let theirs = snapshot([], tags: ["Math", "Old", "Physics"], channels: ["A"])

        let result = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(result.snapshot.library.pinnedTags, ["Math", "Cooking", "Physics"])
        XCTAssertEqual(result.snapshot.library.pinnedChannels, ["A", "B"])
    }

    func testPlaylistsMergeWholeRecordsAndMissingCatalogKeepsMine() {
        let item = PlaylistItem(videoID: "a", title: "A", channel: "C", durationSeconds: 60)
        let basePlaylist = PlaylistRecord(id: "p1", title: "Course", channel: "C", items: [item])
        let base = snapshot([], playlists: [basePlaylist])
        let mine = snapshot([], playlists: [PlaylistRecord(id: "p1", title: "Mac course", channel: "C", items: [item])])
        let theirs = snapshot([], playlists: [basePlaylist])

        let oneSided = ShelfMerger.merge(base: base, mine: mine, theirs: theirs)
        XCTAssertEqual(oneSided.snapshot.playlists[0].title, "Mac course")
        XCTAssertTrue(oneSided.conflicts.isEmpty)

        let both = ShelfMerger.merge(
            base: base,
            mine: mine,
            theirs: snapshot([], playlists: [PlaylistRecord(id: "p1", title: "Web course", channel: "C", items: [item])])
        )
        XCTAssertEqual(both.conflicts.first?.kind, .playlist)
        let resolved = ShelfMerger.resolve(both, choices: [both.conflicts[0].presenceKey: .theirs])
        XCTAssertEqual(resolved.playlists[0].title, "Web course")

        let noCatalog = ShelfMerger.merge(
            base: base,
            mine: mine,
            theirs: snapshot([])
        )
        XCTAssertEqual(noCatalog.snapshot.playlists.count, 1)
        XCTAssertTrue(noCatalog.conflicts.isEmpty)
    }

    func testMergeBaseStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TubeShelfMergeTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MergeBaseStore(directory: directory)
        let value = snapshot([video("a", note: "base")], tags: ["Math"], channels: ["A"])
        try store.save(value)
        XCTAssertEqual(store.load(), value)
        store.clear()
        XCTAssertNil(store.load())
    }
}
