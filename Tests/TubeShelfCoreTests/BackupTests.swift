import XCTest
@testable import TubeShelfCore

final class BackupTests: XCTestCase {
    private func sampleLibrary() -> Library {
        var library = Library()
        library.add(Video(
            youtubeID: "dQw4w9WgXcQ",
            title: "Never Gonna Give You Up",
            channel: "Rick Astley",
            tags: ["Music"],
            note: "saved for later",
            durationSeconds: 213,
            isFavorite: true
        ))
        library.add(Video(
            youtubeID: "jNQXAC9IVRw",
            title: "Me at the zoo",
            channel: "jawed",
            tags: ["Film & Video"]
        ))
        library.pin("Music")
        return library
    }

    func testRoundTripPreservesEverything() throws {
        let original = sampleLibrary()
        let data = try ShelfBackup.encode(original)
        let restored = try ShelfBackup.decode(data)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.pinnedTags, ["Music"])
        XCTAssertEqual(restored.videos.first?.note, "saved for later")
        XCTAssertTrue(restored.videos.first?.isFavorite == true)
    }

    func testEnvelopeCarriesFormatAndVersion() throws {
        let data = try ShelfBackup.encode(sampleLibrary())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["format"] as? String, ShelfBackup.format)
        XCTAssertEqual(object["version"] as? Int, ShelfBackup.version)
        XCTAssertNotNil(object["exportedAt"])
        XCTAssertNotNil(object["library"])
    }

    func testRawLibraryFileIsAccepted() throws {
        let raw = """
        {"videos":[{"youtubeID":"dQw4w9WgXcQ","title":"Old"}],"pinnedTags":[]}
        """
        let library = try ShelfBackup.decode(Data(raw.utf8))
        XCTAssertEqual(library.count, 1)
        XCTAssertEqual(library.videos[0].title, "Old")
    }

    func testForeignJSONIsRejected() {
        let foreign = """
        {"name":"Not a shelf","items":[1,2,3]}
        """
        XCTAssertThrowsError(try ShelfBackup.decode(Data(foreign.utf8))) { error in
            XCTAssertEqual(error as? ShelfBackup.BackupError, .notABackup)
        }
    }

    func testFutureFormatIsRejectedWithAClearReason() throws {
        var data = try ShelfBackup.encode(sampleLibrary())
        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(
            of: "\"version\" : \(ShelfBackup.version)",
            with: "\"version\" : \(ShelfBackup.version + 1)"
        )
        data = Data(text.utf8)
        XCTAssertThrowsError(try ShelfBackup.decode(data)) { error in
            XCTAssertEqual(error as? ShelfBackup.BackupError, .newerVersion(ShelfBackup.version + 1))
        }
    }

    func testEmptyDataIsRejected() {
        XCTAssertThrowsError(try ShelfBackup.decode(Data())) { error in
            XCTAssertEqual(error as? ShelfBackup.BackupError, .empty)
        }
    }

    func testFileRoundTripThroughBackupService() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Nested/My Backup.json")
        let service = BackupService()
        let original = sampleLibrary()
        try service.write(original, to: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try service.read(from: url), original)

        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(raw?["format"] as? String, ShelfBackup.format)
    }

    func testSuggestedFileNameCarriesDateTimeAndZone() {
        let zone = TimeZone(identifier: "Asia/Bangkok")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14, hour: 15, minute: 42, second: 7
        ))!

        let name = ShelfBackup.suggestedFileName(for: date, timeZone: zone)
        let label = (zone.abbreviation(for: date) ?? "GMT+7")
            .replacingOccurrences(of: ":", with: "-")
        XCTAssertEqual(name, "TubeShelf 2026-11-14 15.42.07 \(label).json")
        XCTAssertTrue(name.hasSuffix(".json"))
    }

    func testSuggestedFileNameCarriesAndSanitizesProfileName() {
        let zone = TimeZone(identifier: "Asia/Bangkok")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 14, hour: 15, minute: 42, second: 7
        ))!
        let label = (zone.abbreviation(for: date) ?? "GMT+7")
            .replacingOccurrences(of: ":", with: "-")

        let name = ShelfBackup.suggestedFileName(
            for: date,
            timeZone: zone,
            profileName: "Work / Study: 2026",
            machineName: "My Mac"
        )
        XCTAssertEqual(
            name,
            "TubeShelf Work - Study - 2026 @ My Mac 2026-11-14 15.42.07 \(label).json"
        )
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: name), "Work - Study - 2026")
    }

    func testProfileNameParsesNewAndOldFileNames() {
        let new = "TubeShelf My Shelf 2026-11-14 15.42.07 PST.json"
        let machine = "TubeShelf My Shelf @ My Mac 2026-11-14 15.42.07 PST.json"
        let machineWeb = "TubeShelf My Shelf @ Work PC 2026-11-14 15.42.07-web.json"
        let web = "TubeShelf My Shelf 2026-11-14 15.42.07 PST-web.json"
        let webNoZone = "TubeShelf My Shelf 2026-11-14 15.42.07-web.json"
        let old = "TubeShelf 2026-11-14 15.42.07 PST.json"
        let oldWeb = "TubeShelf 2026-11-14 15.42.07-web.json"
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: new), "My Shelf")
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: machine), "My Shelf")
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: machineWeb), "My Shelf")
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: web), "My Shelf")
        XCTAssertEqual(ShelfBackup.profileName(fromFileName: webNoZone), "My Shelf")
        XCTAssertNil(ShelfBackup.profileName(fromFileName: old))
        XCTAssertNil(ShelfBackup.profileName(fromFileName: oldWeb))
        XCTAssertNil(ShelfBackup.profileName(fromFileName: "demo-shelf.json"))
    }

    func testSanitizedProfileNameDropsPathHostileCharacters() {
        XCTAssertEqual(ShelfBackup.sanitizedProfileName("A/B:C*?\"<>|@"), "A - B - C")
        XCTAssertEqual(ShelfBackup.sanitizedProfileName("   "), "")
        XCTAssertEqual(ShelfBackup.sanitizedProfileName(nil), "")
    }

    func testSuggestedFileNameIsSafeForSyncFolders() {
        // Half-hour zones produce an abbreviation like "GMT+5:30"; the colon must
        // not survive into a filename that a sync client has to handle.
        let zone = TimeZone(identifier: "Asia/Kolkata")!
        let name = ShelfBackup.suggestedFileName(for: Date(), timeZone: zone)
        XCTAssertFalse(name.contains(":"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(" \\(null)"))
    }
}
