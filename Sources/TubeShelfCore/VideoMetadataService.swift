import Foundation

public enum MetadataError: LocalizedError, Sendable {
    case notAYouTubeLink
    case videoUnavailable

    public var errorDescription: String? {
        switch self {
        case .notAYouTubeLink: "That does not look like a YouTube link."
        case .videoUnavailable: "YouTube would not return details for that video. It may be private, age-restricted or deleted."
        }
    }
}

public struct VideoMetadata: Sendable, Equatable {
    public var videoID: String
    public var title: String
    public var channel: String
    public var description: String
    public var durationSeconds: Int?

    public init(
        videoID: String,
        title: String,
        channel: String,
        description: String = "",
        durationSeconds: Int? = nil
    ) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.description = description
        self.durationSeconds = durationSeconds
    }
}

struct OEmbedPayload: Decodable, Sendable {
    let title: String
    let author_name: String
    let thumbnail_url: String?
}

/// No API key, no OAuth: oEmbed gives title and channel, and the watch page is
/// scraped best-effort for the description and duration that help the tagger.
public struct YouTubeMetadataService: Sendable {
    public init() {}

    public func fetch(videoID: String) async throws -> VideoMetadata {
        guard YouTubeURL.isVideoID(videoID) else { throw MetadataError.notAYouTubeLink }

        let oembed = try? await fetchOEmbed(videoID: videoID)
        let page = try? await fetchWatchPage(videoID: videoID)

        // oEmbed answers 401 for videos that disallow embedding, even when the
        // watch page plays fine. Fall back to that page for title and channel.
        let title = oembed?.title ?? page.flatMap(MetaScraper.title(fromHTML:))
        let channel = oembed?.author_name ?? page.flatMap(MetaScraper.channel(fromHTML:))
        guard let title, let channel else { throw MetadataError.videoUnavailable }

        var description = ""
        var duration: Int?
        if let page {
            description = MetaScraper.description(fromHTML: page) ?? ""
            duration = MetaScraper.durationSeconds(fromHTML: page)
        }

        return VideoMetadata(
            videoID: videoID,
            title: title,
            channel: channel,
            description: description,
            durationSeconds: duration
        )
    }

    private func fetchOEmbed(videoID: String) async throws -> OEmbedPayload {
        let watch = YouTubeURL.watchURL(for: videoID).absoluteString
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            throw MetadataError.videoUnavailable
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: watch),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw MetadataError.videoUnavailable }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("TubeShelf/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw MetadataError.videoUnavailable
        }
        do {
            return try JSONDecoder().decode(OEmbedPayload.self, from: data)
        } catch {
            throw MetadataError.videoUnavailable
        }
    }

    private func fetchWatchPage(videoID: String) async throws -> String {
        var request = URLRequest(url: YouTubeURL.watchURL(for: videoID))
        request.timeoutInterval = 15
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { throw MetadataError.videoUnavailable }
        return html
    }
}

/// Small, forgiving scrapers. Every one of them returns nil rather than guessing.
enum MetaScraper {
    static func title(fromHTML html: String) -> String? {
        if let raw = firstCapture(#"<meta property="og:title" content="([^"]*)""#, in: html) {
            let decoded = decodeHTMLEntities(raw)
            if !decoded.isEmpty { return decoded }
        }
        if let raw = firstCapture(#""title":"((?:[^"\\]|\\.)*)""#, in: html),
           let decoded = decodeJSONString(raw),
           !decoded.isEmpty {
            return decoded
        }
        return nil
    }

    static func channel(fromHTML html: String) -> String? {
        let jsonPatterns = [
            #""ownerChannelName":"((?:[^"\\]|\\.)*)""#,
            #""author":"((?:[^"\\]|\\.)*)""#
        ]
        for pattern in jsonPatterns {
            if let raw = firstCapture(pattern, in: html),
               let decoded = decodeJSONString(raw),
               !decoded.isEmpty {
                return decoded
            }
        }
        if let raw = firstCapture(#"<link itemprop="name" content="([^"]*)""#, in: html) {
            let decoded = decodeHTMLEntities(raw)
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    static func description(fromHTML html: String) -> String? {
        // Recommendations can ship their own shortDescription before the real
        // player response. Only trust the one inside videoDetails.
        let details = scopedToVideoDetails(html)
        if let raw = firstCapture(#""shortDescription":"((?:[^"\\]|\\.)*)""#, in: details),
           let decoded = decodeJSONString(raw),
           !decoded.isEmpty {
            return decoded
        }
        if let raw = firstCapture(#"<meta name="description" content="([^"]*)""#, in: html) {
            let decoded = decodeHTMLEntities(raw)
            return decoded.isEmpty ? nil : decoded
        }
        return nil
    }

    static func durationSeconds(fromHTML html: String) -> Int? {
        if let raw = firstCapture(#""lengthSeconds":"(\d+)""#, in: scopedToVideoDetails(html)) {
            return Int(raw)
        }
        return nil
    }

    /// Everything after the player's `videoDetails` marker, or the whole page
    /// when the marker is absent (older markup).
    private static func scopedToVideoDetails(_ html: String) -> String {
        guard let range = html.range(of: #""videoDetails""#) else { return html }
        return String(html[range.upperBound...])
    }

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captured = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[captured])
    }

    static func decodeJSONString(_ raw: String) -> String? {
        let wrapped = "\"\(raw)\""
        guard let data = wrapped.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    static func decodeHTMLEntities(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
