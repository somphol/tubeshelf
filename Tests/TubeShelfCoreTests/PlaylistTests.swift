import XCTest
@testable import TubeShelfCore

final class PlaylistTests: XCTestCase {
    private func html(with data: [String: Any]) throws -> String {
        let json = try JSONSerialization.data(withJSONObject: data)
        let text = String(decoding: json, as: UTF8.self)
        return "<html><script>var ytInitialData = \(text);</script></html>"
    }

    private func fixture() -> [String: Any] {
        func item(_ id: String, _ title: String, _ channel: String, _ length: String) -> [String: Any] {
            [
                "playlistVideoRenderer": [
                    "videoId": id,
                    "title": ["runs": [["text": title]]],
                    "shortBylineText": ["runs": [["text": channel]]],
                    "lengthText": ["simpleText": length]
                ]
            ]
        }

        return [
            "metadata": ["playlistMetadataRenderer": ["title": "Math: Trigonometry"]],
            "contents": [
                "twoColumnBrowseResultsRenderer": [
                    "tabs": [[
                        "tabRenderer": [
                            "content": [
                                "sectionListRenderer": [
                                    "contents": [[
                                        "itemSectionRenderer": [
                                            "contents": [
                                                item("ovLbCvq7FNA", "Trigonometry", "Eugene", "16:29"),
                                                item("dQw4w9WgXcQ", "Never Gonna Give You Up", "Rick Astley", "3:33"),
                                                item("ovLbCvq7FNA", "Duplicate", "Eugene", "16:29"),
                                                item("tooshort", "Bad id", "Nobody", "1:00")
                                            ]
                                        ]
                                    ]]
                                ]
                            ]
                        ]
                    ]]
                ]
            ]
        ]
    }

    func testParsesItemsDedupesAndSkipsInvalidIDs() throws {
        let metadata = try PlaylistParser.parse(
            html: try html(with: fixture()),
            playlistID: "PLsut0F29QsHjQmcTxUIjlfrPxa2ZbVetP",
            limit: 50
        )

        XCTAssertEqual(metadata.title, "Math: Trigonometry")
        XCTAssertEqual(metadata.items.count, 2)
        XCTAssertEqual(metadata.items[0].videoID, "ovLbCvq7FNA")
        XCTAssertEqual(metadata.items[0].durationSeconds, 989)
        XCTAssertEqual(metadata.items[1].channel, "Rick Astley")
        XCTAssertFalse(metadata.truncated)
    }

    func testRespectsTheLimitAndFlagsTruncation() throws {
        let metadata = try PlaylistParser.parse(
            html: try html(with: fixture()),
            playlistID: "PLsut0F29QsHjQmcTxUIjlfrPxa2ZbVetP",
            limit: 1
        )
        XCTAssertEqual(metadata.items.count, 1)
        XCTAssertTrue(metadata.truncated)
    }

    func testRejectsAPageWithoutPlaylistData() {
        XCTAssertThrowsError(
            try PlaylistParser.parse(html: "<html>nothing</html>", playlistID: "PL1234567890", limit: 10)
        ) { error in
            XCTAssertEqual(error as? PlaylistError, .unreadable)
        }
    }

    func testDurationsAddedByHand() {
        XCTAssertEqual(PlaylistParser.parseDuration("16:29"), 989)
        XCTAssertEqual(PlaylistParser.parseDuration("1:02:03"), 3723)
        XCTAssertNil(PlaylistParser.parseDuration("soon"))
    }

    func testPlaylistIDsFromEveryLinkShape() {
        let id = "PLsut0F29QsHjQmcTxUIjlfrPxa2ZbVetP"
        let inputs = [
            "https://www.youtube.com/playlist?list=\(id)",
            "https://www.youtube.com/watch?v=ovLbCvq7FNA&list=\(id)&index=21",
            "https://youtu.be/ovLbCvq7FNA?list=\(id)",
            "youtube.com/playlist?list=\(id)&si=abc",
            "\"https://www.youtube.com/playlist?list=\(id)\""
        ]
        for input in inputs {
            XCTAssertEqual(YouTubeURL.playlistID(from: input), id, input)
        }
        XCTAssertNil(YouTubeURL.playlistID(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(YouTubeURL.playlistID(from: "https://example.com/?list=notenough"))
    }
}
