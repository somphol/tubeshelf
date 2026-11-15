import Foundation

/// Parses the many shapes a YouTube link arrives in and produces the canonical
/// 11-character video identifier used everywhere else in the app.
public enum YouTubeURL {
    public static let idLength = 11

    private static let idCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

    public static func isVideoID(_ candidate: String) -> Bool {
        guard candidate.count == idLength else { return false }
        return candidate.unicodeScalars.allSatisfy(idCharacters.contains)
    }

    /// Accepts `watch?v=`, `youtu.be/`, `shorts/`, `embed/`, `live/`, `v/`,
    /// bare IDs, and links pasted with tracking parameters attached.
    public static func videoID(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Strip wrapping angle brackets and quotes people copy from chat apps.
        if text.hasPrefix("<"), text.hasSuffix(">") {
            text = String(text.dropFirst().dropLast())
        }
        let quoteMarks: [Character] = ["\"", "'", "\u{201C}", "\u{201D}"]
        while let first = text.first, quoteMarks.contains(first) { text.removeFirst() }
        while let last = text.last, quoteMarks.contains(last) { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if isVideoID(text) { return text }

        let withScheme = text.contains("://") || text.hasPrefix("//") ? text : "https://" + text
        let normalized = withScheme.hasPrefix("//") ? "https:" + withScheme : withScheme

        guard let components = URLComponents(string: normalized),
              let host = components.host?.lowercased()
        else { return nil }

        let isYouTubeHost = host == "youtu.be"
            || host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
        guard isYouTubeHost else { return nil }

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        if host == "youtu.be" {
            return pathParts.first.flatMap { isVideoID($0) ? $0 : nil }
        }

        if let first = pathParts.first,
           ["shorts", "embed", "live", "v", "e"].contains(first),
           pathParts.count >= 2,
           isVideoID(pathParts[1]) {
            return pathParts[1]
        }

        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isVideoID(value) {
            return value
        }

        return nil
    }

    /// Playlist ids arrive as `list=` on watch, playlist and share links.
    public static func playlistID(from raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let markers: [Character] = ["\"", "'"]
        while let first = text.first, markers.contains(first) { text.removeFirst() }
        while let last = text.last, markers.contains(last) { text.removeLast() }

        let withScheme = text.contains("://") ? text : "https://" + text
        guard let components = URLComponents(string: withScheme),
              let value = components.queryItems?.first(where: { $0.name == "list" })?.value
        else { return nil }

        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        guard value.count >= 10,
              value.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return value
    }

    public static func watchURL(for videoID: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
    }

    public static func embedURL(for videoID: String, autoplay: Bool) -> URL {
        var value = "https://www.youtube-nocookie.com/embed/\(videoID)?rel=0&modestbranding=1&playsinline=1"
        if autoplay { value += "&autoplay=1" }
        return URL(string: value)!
    }

    /// Highest resolution first; callers fall back in order on 404.
    public static func thumbnailCandidates(for videoID: String) -> [URL] {
        ["maxresdefault", "sddefault", "hqdefault", "mqdefault"].compactMap {
            URL(string: "https://i.ytimg.com/vi/\(videoID)/\($0).jpg")
        }
    }

    public static func thumbnailURL(for videoID: String) -> URL {
        thumbnailCandidates(for: videoID)[0]
    }
}
