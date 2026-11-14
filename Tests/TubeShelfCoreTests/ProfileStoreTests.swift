import XCTest
@testable import TubeShelfCore

final class ProfileStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-profiles-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func legacyLibrary() -> Library {
        var library = Library()
        library.add(Video(youtubeID: "dQw4w9WgXcQ", title: "Old shelf", channel: "C", tags: ["Music"]))
        library.pin("Music")
        return library
    }

    func testFirstRunAdoptsTheExistingLibraryWithoutDeletingIt() throws {
        let store = ProfileStore(root: root)
        try LibraryStore(directory: root).save(legacyLibrary())

        let profiles = try store.profiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles[0].name, "My Shelf")
        XCTAssertNotNil(profiles[0].importedFrom)

        let adopted = try store.libraryStore(for: profiles[0]).load()
        XCTAssertEqual(adopted.videos.first?.title, "Old shelf")
        XCTAssertEqual(adopted.pinnedTags, ["Music"])

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: store.legacyLibraryURL.path),
            "the pre-profile file must survive as a backup"
        )
    }

    func testSecondRunIsStableAndDoesNotDuplicate() throws {
        let store = ProfileStore(root: root)
        let first = try store.profiles()
        let second = try store.profiles()
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(second.count, 1)
    }

    func testEmptyInstallCreatesOneEmptyProfile() throws {
        let store = ProfileStore(root: root)
        let profiles = try store.profiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertTrue(try store.libraryStore(for: profiles[0]).load().isEmpty)
    }

    func testProfilesAreIsolatedFromEachOther() throws {
        let store = ProfileStore(root: root)
        let personal = try store.profiles()[0]
        try store.libraryStore(for: personal).save(legacyLibrary())

        var friend = Library()
        friend.add(Video(youtubeID: "jNQXAC9IVRw", title: "Friend's shelf", channel: "C", tags: ["Travel"]))
        let imported = try store.create(name: "Friend", library: friend, importedFrom: "friend.json")

        XCTAssertEqual(try store.libraryStore(for: personal).load().count, 1)
        let friendShelf = try store.libraryStore(for: imported).load()
        XCTAssertEqual(friendShelf.count, 1)
        XCTAssertEqual(friendShelf.videos.first?.title, "Friend's shelf")

        // Writing to the friend profile must not move the personal one.
        try store.libraryStore(for: imported).save(Library())
        XCTAssertEqual(try store.libraryStore(for: personal).load().count, 1)
    }

    func testRenamePersistsAcrossReloads() throws {
        let store = ProfileStore(root: root)
        var profile = try store.profiles()[0]
        profile.name = "Research"
        try store.saveMetadata(profile)

        let reloaded = try store.profiles()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded[0].name, "Research")
    }

    func testTrashRemovesTheProfileButKeepsOtherShelves() throws {
        let store = ProfileStore(root: root)
        let keep = try store.profiles()[0]
        let doomed = try store.create(name: "Old trip", library: Library(), importedFrom: nil)

        let trashedURL = try store.trash(doomed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory(for: doomed).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: trashedURL.path), "the folder lands in the Trash")

        let remaining = try store.profiles()
        XCTAssertEqual(remaining.map(\.id), [keep.id])
    }

    func testUniqueNamesAvoidCollisions() {
        let store = ProfileStore(root: root)
        let existing = [
            Profile(name: "Friend"),
            Profile(name: "friend 2")
        ]
        XCTAssertEqual(store.uniqueName("Friend", among: existing), "Friend 3")
        XCTAssertEqual(store.uniqueName("  Work  ", among: existing), "Work")
        XCTAssertEqual(store.uniqueName("   ", among: existing), "Shelf")
    }

    func testCorruptProfileMetadataIsSkippedNotFatal() throws {
        let store = ProfileStore(root: root)
        let profile = try store.profiles()[0]
        let meta = store.directory(for: profile).appendingPathComponent("profile.json")
        try Data("not json".utf8).write(to: meta)

        // The folder is unreadable, so the scan falls back to creating a fresh
        // profile instead of crashing.
        let profiles = try store.profiles()
        XCTAssertEqual(profiles.count, 1)
        XCTAssertNotEqual(profiles[0].id, profile.id)
    }

    func testProfileSubtitleMentionsImport() {
        let imported = Profile(name: "Friend", importedFrom: "Trip.json")
        XCTAssertTrue(imported.subtitle.contains("Trip.json"))
        XCTAssertTrue(Profile(name: "Mine").subtitle.hasPrefix("Created"))
    }
}
