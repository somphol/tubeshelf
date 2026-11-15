import XCTest
@testable import TubeShelfCore

final class PlaylistCatalogTests: XCTestCase {
    private func items(_ count: Int) -> [PlaylistItem] {
        (0..<count).map {
            PlaylistItem(
                videoID: String(format: "vid%08d", $0),
                title: "Chapter \($0 + 1)",
                channel: "3Blue1Brown",
                durationSeconds: 600 + $0
            )
        }
    }

    private func record(_ suffix: String = "1", addedAt: Date = Date(timeIntervalSince1970: 1_000)) -> PlaylistRecord {
        PlaylistRecord(
            id: "PL\(suffix)",
            title: "Essence of linear algebra",
            channel: "3Blue1Brown",
            items: items(16),
            addedAt: addedAt,
            watchedItemIDs: ["vid00000000", "vid00000001"]
        )
    }

    func testDerivedCountsAndProgress() {
        let playlist = record()
        XCTAssertEqual(playlist.chapterCount, 16)
        XCTAssertEqual(playlist.watchedCount, 2)
        XCTAssertEqual(playlist.progress, 2.0 / 16.0, accuracy: 0.0001)
        XCTAssertEqual(playlist.coverVideoID, "vid00000000")
        XCTAssertEqual(playlist.shareURL?.absoluteString,
                       "https://www.youtube.com/playlist?list=PL1")
    }

    func testTickingIsCaseInsensitiveAndReversible() {
        var playlist = record()
        playlist.setWatched(true, videoID: "VID00000002")
        XCTAssertTrue(playlist.isWatched("vid00000002"))
        XCTAssertEqual(playlist.watchedCount, 3)

        playlist.setWatched(true, videoID: "vid00000002")
        XCTAssertEqual(playlist.watchedCount, 3, "no duplicates")

        playlist.setWatched(false, videoID: "vid00000002")
        XCTAssertFalse(playlist.isWatched("vid00000002"))
    }

    func testRefreshKeepsOnlyTicksThatStillExist() {
        var playlist = record()
        playlist.replaceItems([
            PlaylistItem(videoID: "vid00000000", title: "Chapter 1", channel: "C", durationSeconds: nil),
            PlaylistItem(videoID: "NEWVID00001", title: "New chapter", channel: "C", durationSeconds: nil)
        ])
        XCTAssertEqual(playlist.chapterCount, 2)
        XCTAssertEqual(playlist.watchedCount, 1, "the vanished chapter's tick is dropped")
        XCTAssertTrue(playlist.isWatched("vid00000000"))
    }

    func testStoreRoundTripAndOrdering() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlists-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PlaylistStore(directory: directory)

        XCTAssertTrue(try store.load().isEmpty)

        let older = record("old", addedAt: Date(timeIntervalSince1970: 100))
        let newer = record("new", addedAt: Date(timeIntervalSince1970: 900))
        try store.save([older, newer])

        let loaded = try store.load()
        XCTAssertEqual(loaded.map(\.id), ["PLnew", "PLold"], "newest first")
        XCTAssertEqual(loaded.first, newer)
        XCTAssertEqual(loaded.first?.watchedItemIDs, newer.watchedItemIDs)
    }

    func testCorruptCatalogIsQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("playlists-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = PlaylistStore(directory: directory)
        try Data("not json".utf8).write(to: store.fileURL)

        XCTAssertTrue(try store.load().isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("playlists-corrupt-") })
    }

    func testBackupCarriesTheCatalogAndStaysReadableWithoutOne() throws {
        var library = Library()
        library.add(Video(youtubeID: "dQw4w9WgXcQ", title: "A", channel: "C"))
        let playlist = record()

        let withCatalog = try ShelfBackup.encode(library, playlists: [playlist])
        let contents = try ShelfBackup.decodeContents(withCatalog)
        XCTAssertEqual(contents.library, library)
        XCTAssertEqual(contents.playlists, [playlist])

        let withoutCatalog = try ShelfBackup.encode(library)
        XCTAssertEqual(try ShelfBackup.decodeContents(withoutCatalog).playlists, [])
    }

    func testOldBackupWithoutPlaylistsStillDecodes() throws {
        let json = """
        {"format":"tubeshelf.backup","version":1,"exportedAt":"2026-11-14T10:00:00Z",
         "library":{"videos":[],"pinnedTags":[]}}
        """
        let contents = try ShelfBackup.decodeContents(Data(json.utf8))
        XCTAssertTrue(contents.library.isEmpty)
        XCTAssertTrue(contents.playlists.isEmpty)
    }
}
