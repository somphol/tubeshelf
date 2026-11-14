import XCTest
@testable import TubeShelfCore

final class YouTubeURLTests: XCTestCase {
    func testEveryAcceptedLinkShapeResolves() {
        let id = "dQw4w9WgXcQ"
        let inputs = [
            "https://www.youtube.com/watch?v=\(id)",
            "https://www.youtube.com/watch?v=\(id)&list=PL123&index=4&t=42s",
            "http://youtube.com/watch?v=\(id)",
            "https://m.youtube.com/watch?v=\(id)",
            "https://music.youtube.com/watch?v=\(id)&feature=share",
            "https://youtu.be/\(id)",
            "https://youtu.be/\(id)?t=90",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/shorts/\(id)?feature=share",
            "https://www.youtube.com/embed/\(id)",
            "https://www.youtube-nocookie.com/embed/\(id)?autoplay=1",
            "https://www.youtube.com/live/\(id)",
            "https://www.youtube.com/v/\(id)",
            "www.youtube.com/watch?v=\(id)",
            "youtu.be/\(id)",
            "  https://youtu.be/\(id)  ",
            "\"https://youtu.be/\(id)\"",
            "<https://youtu.be/\(id)>",
            id
        ]
        for input in inputs {
            XCTAssertEqual(YouTubeURL.videoID(from: input), id, "failed for \(input)")
        }
    }

    func testRejectsNonYouTubeAndMalformedInput() {
        let rejected = [
            "",
            "   ",
            "hello world",
            "https://vimeo.com/123456789",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=tooshort",
            "https://www.youtube.com/watch?v=aaaaaaaaaaaaaa",
            "https://www.youtube.com/channel/UC1234567890",
            "https://www.youtube.com/playlist?list=PL123"
        ]
        for input in rejected {
            XCTAssertNil(YouTubeURL.videoID(from: input), "should reject \(input)")
        }
    }

    func testCanonicalAndAssetURLs() {
        let id = "jNQXAC9IVRw"
        XCTAssertEqual(YouTubeURL.watchURL(for: id).absoluteString, "https://www.youtube.com/watch?v=\(id)")
        XCTAssertEqual(YouTubeURL.thumbnailURL(for: id).absoluteString, "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
        XCTAssertEqual(YouTubeURL.thumbnailCandidates(for: id).count, 4)
        XCTAssertTrue(YouTubeURL.embedURL(for: id, autoplay: true).absoluteString.contains("autoplay=1"))
        XCTAssertTrue(YouTubeURL.embedURL(for: id, autoplay: false).absoluteString.contains("youtube-nocookie.com"))
    }

    func testVideoIDValidationIsExactLength() {
        XCTAssertTrue(YouTubeURL.isVideoID("dQw4w9WgXcQ"))
        XCTAssertTrue(YouTubeURL.isVideoID("__________-"))
        XCTAssertFalse(YouTubeURL.isVideoID("dQw4w9WgXc"))
        XCTAssertFalse(YouTubeURL.isVideoID("dQw4w9WgXcQQ"))
        XCTAssertFalse(YouTubeURL.isVideoID("dQw4w9WgXc!"))
    }
}
