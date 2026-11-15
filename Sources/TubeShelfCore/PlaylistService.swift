import Foundation

public struct PlaylistItem: Sendable, Equatable, Identifiable {
    public let videoID: String
    public let title: String
    public let channel: String
    public let durationSeconds: Int?

    public var id: String { videoID }

    public init(videoID: String, title: String, channel: String, durationSeconds: Int?) {
        self.videoID = videoID
        self.title = title
        self.channel = channel
        self.durationSeconds = durationSeconds
    }
}

public struct PlaylistMetadata: Sendable, Equatable {
    public let playlistID: String
    public let title: String
    public let items: [PlaylistItem]
    public let truncated: Bool

    public init(playlistID: String, title: String, items: [PlaylistItem], truncated: Bool) {
        self.playlistID = playlistID
        self.title = title
        self.items = items
        self.truncated = truncated
    }
}

public enum PlaylistError: LocalizedError, Sendable {
    case notAPlaylist
    case unreadable
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAPlaylist: "That link does not contain a playlist id."
        case .unreadable: "YouTube did not return a readable playlist page."
        case .empty: "That playlist appears to have no videos."
        }
    }
}

/// Reads a playlist from its public page. No API key: the page ships the first
/// batch of items inside `ytInitialData`, which is the same data the browser uses
/// before you scroll.
public struct PlaylistService: Sendable {
    public init() {}

    public func fetch(playlistID: String, limit: Int = 200) async throws -> PlaylistMetadata {
        guard let url = URL(string: "https://www.youtube.com/playlist?list=\(playlistID)&hl=en&gl=US") else {
            throw PlaylistError.notAPlaylist
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let html = String(data: data, encoding: .utf8)
        else { throw PlaylistError.unreadable }

        return try PlaylistParser.parse(html: html, playlistID: playlistID, limit: limit)
    }
}

enum PlaylistParser {
    static func parse(html: String, playlistID: String, limit: Int) throws -> PlaylistMetadata {
        guard let data = ytInitialData(from: html),
              let root = try? JSONSerialization.jsonObject(with: data)
        else { throw PlaylistError.unreadable }

        var seen = Set<String>()
        var items: [PlaylistItem] = []
        collectItems(root, into: &items, seen: &seen, limit: limit)

        guard !items.isEmpty else { throw PlaylistError.empty }

        return PlaylistMetadata(
            playlistID: playlistID,
            title: playlistTitle(from: root) ?? pageTitle(from: html) ?? "Playlist",
            items: items,
            // The page only ships the first batch; a continuation token means the
            // playlist is longer than what we could read in one request.
            truncated: items.count >= limit || hasContinuation(root)
        )
    }

    static func ytInitialData(from html: String) -> Data? {
        let patterns = [
            #"var ytInitialData = (\{.*?\});</script>"#,
            #"ytInitialData"?\s*[:=]\s*(\{.*?\});"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            guard let match = regex.firstMatch(in: html, options: [], range: range),
                  match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: html)
            else { continue }
            return String(html[captured]).data(using: .utf8)
        }
        return nil
    }

    /// Walks the tree in document order so the playlist's own ordering survives.
    /// Supports both the classic `playlistVideoRenderer` and the current
    /// `lockupViewModel` markup.
    private static func collectItems(
        _ node: Any,
        into result: inout [PlaylistItem],
        seen: inout Set<String>,
        limit: Int
    ) {
        if result.count >= limit { return }

        if let dictionary = node as? [String: Any] {
            if let renderer = dictionary["playlistVideoRenderer"] as? [String: Any],
               let videoID = renderer["videoId"] as? String,
               YouTubeURL.isVideoID(videoID),
               seen.insert(videoID).inserted {
                result.append(PlaylistItem(
                    videoID: videoID,
                    title: title(from: renderer) ?? "Untitled",
                    channel: channel(from: renderer) ?? "",
                    durationSeconds: durationSeconds(from: renderer)
                ))
            } else if let lockup = dictionary["lockupViewModel"] as? [String: Any],
                      lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
                      let videoID = lockup["contentId"] as? String,
                      YouTubeURL.isVideoID(videoID),
                      seen.insert(videoID).inserted {
                result.append(PlaylistItem(
                    videoID: videoID,
                    title: lockupTitle(from: lockup) ?? "Untitled",
                    channel: lockupChannel(from: lockup) ?? "",
                    durationSeconds: lockupDuration(from: lockup)
                ))
            }

            for value in dictionary.values {
                collectItems(value, into: &result, seen: &seen, limit: limit)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectItems(value, into: &result, seen: &seen, limit: limit)
            }
        }
    }

    private static func lockupTitle(from lockup: [String: Any]) -> String? {
        guard let metadata = lockup["metadata"] as? [String: Any],
              let model = metadata["lockupMetadataViewModel"] as? [String: Any],
              let title = model["title"] as? [String: Any],
              let content = title["content"] as? String,
              !content.isEmpty
        else { return nil }
        return content
    }

    private static func lockupChannel(from lockup: [String: Any]) -> String? {
        guard let metadata = lockup["metadata"] as? [String: Any],
              let model = metadata["lockupMetadataViewModel"] as? [String: Any],
              let contentMetadata = model["metadata"] as? [String: Any],
              let viewModel = contentMetadata["contentMetadataViewModel"] as? [String: Any],
              let rows = viewModel["metadataRows"] as? [[String: Any]],
              let parts = rows.first?["metadataParts"] as? [[String: Any]],
              let text = parts.first?["text"] as? [String: Any],
              let content = text["content"] as? String
        else { return nil }
        return content
    }

    private static func lockupDuration(from lockup: [String: Any]) -> Int? {
        guard let image = lockup["contentImage"] as? [String: Any],
              let thumbnail = image["thumbnailViewModel"] as? [String: Any],
              let overlays = thumbnail["overlays"] as? [[String: Any]]
        else { return nil }

        for overlay in overlays {
            guard let bottom = overlay["thumbnailBottomOverlayViewModel"] as? [String: Any],
                  let badges = bottom["badges"] as? [[String: Any]]
            else { continue }
            for badge in badges {
                guard let model = badge["thumbnailBadgeViewModel"] as? [String: Any],
                      let text = model["text"] as? String
                else { continue }
                if let seconds = parseDuration(text) { return seconds }
            }
        }
        return nil
    }

    private static func hasContinuation(_ node: Any) -> Bool {
        if let dictionary = node as? [String: Any] {
            if dictionary["continuationCommand"] != nil { return true }
            return dictionary.values.contains { hasContinuation($0) }
        }
        if let array = node as? [Any] {
            return array.contains { hasContinuation($0) }
        }
        return false
    }

    private static func pageTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "<title>(.*?)</title>", options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..<html.endIndex, in: html)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: html)
        else { return nil }

        let title = String(html[range])
            .replacingOccurrences(of: " - YouTube", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }

    private static func title(from renderer: [String: Any]) -> String? {
        if let title = renderer["title"] as? [String: Any] {
            if let runs = title["runs"] as? [[String: Any]] {
                let text = runs.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty { return text }
            }
            if let simple = title["simpleText"] as? String, !simple.isEmpty { return simple }
        }
        return nil
    }

    private static func channel(from renderer: [String: Any]) -> String? {
        guard let byline = renderer["shortBylineText"] as? [String: Any],
              let runs = byline["runs"] as? [[String: Any]],
              let text = runs.first?["text"] as? String
        else { return nil }
        return text
    }

    private static func durationSeconds(from renderer: [String: Any]) -> Int? {
        guard let length = renderer["lengthText"] as? [String: Any],
              let text = length["simpleText"] as? String
        else { return nil }
        return parseDuration(text)
    }

    static func parseDuration(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return nil
        }
    }

    private static func playlistTitle(from root: Any) -> String? {
        var found: String?
        func walk(_ node: Any) {
            guard found == nil else { return }
            if let dictionary = node as? [String: Any] {
                if let meta = dictionary["playlistMetadataRenderer"] as? [String: Any],
                   let title = meta["title"] as? String, !title.isEmpty {
                    found = title
                    return
                }
                for value in dictionary.values { walk(value) }
            } else if let array = node as? [Any] {
                for value in array { walk(value) }
            }
        }
        walk(root)
        return found
    }
}
