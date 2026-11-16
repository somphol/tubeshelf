import XCTest
@testable import TubeShelfCore

/// The web editor must produce a file this decoder accepts. Regenerate the
/// fixture from tubeshelf-web when the format changes.
final class WebExportTests: XCTestCase {
    func testWebExportedBackupDecodes() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/web-export.json")
        let contents = try BackupService().readContents(from: url)

        XCTAssertEqual(contents.library.count, 8)
        XCTAssertEqual(contents.playlists.count, 1)

        let edited = contents.library.videos.first { $0.youtubeID == "VEtU4Co08yY" }
        XCTAssertEqual(edited?.note, "Edited on the web")
        XCTAssertEqual(edited?.tags, ["Cooking", "Test Tag"])
        XCTAssertEqual(edited?.isFavorite, true)
        XCTAssertEqual(edited?.watchStatus, .done)
        XCTAssertNotNil(edited?.addedAt)

        let added = contents.library.videos.first { $0.youtubeID == "kJQP7kiw5Fk" }
        XCTAssertEqual(added?.title, "Luis Fonsi - Despacito ft. Daddy Yankee")
        XCTAssertEqual(added?.channel, "LuisFonsiVEVO")
        XCTAssertNil(added?.durationSeconds)
        XCTAssertNotNil(added?.addedAt)
    }
}
