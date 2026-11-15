import Foundation

public enum WatchStatus: String, Codable, CaseIterable, Sendable {
    case unwatched
    case watching
    case done

    public var label: String {
        switch self {
        case .unwatched: "Unwatched"
        case .watching: "Watching"
        case .done: "Watched"
        }
    }
}

/// One saved YouTube video. The YouTube ID is the durable identity; `id` exists
/// only so SwiftUI and the deck can address a row without depending on it.
public struct Video: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var youtubeID: String
    public var title: String
    public var channel: String
    public var tags: [String]
    public var note: String
    public var addedAt: Date
    public var durationSeconds: Int?
    public var isFavorite: Bool
    public var watchStatus: WatchStatus

    public init(
        id: UUID = UUID(),
        youtubeID: String,
        title: String,
        channel: String,
        tags: [String] = [],
        note: String = "",
        addedAt: Date = Date(),
        durationSeconds: Int? = nil,
        isFavorite: Bool = false,
        watchStatus: WatchStatus = .unwatched
    ) {
        self.id = id
        self.youtubeID = youtubeID
        self.title = title
        self.channel = channel
        self.tags = TagNormalizer.merge(tags)
        self.note = note
        self.addedAt = Video.normalized(addedAt)
        self.durationSeconds = durationSeconds
        self.isFavorite = isFavorite
        self.watchStatus = watchStatus
    }

    // Tolerant decoding so a library written by an older build still opens.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        youtubeID = try container.decode(String.self, forKey: .youtubeID)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? ""
        tags = TagNormalizer.merge(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        addedAt = Video.normalized(addedAt)
        durationSeconds = try container.decodeIfPresent(Int.self, forKey: .durationSeconds)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        watchStatus = try container.decodeIfPresent(WatchStatus.self, forKey: .watchStatus) ?? .unwatched
    }

    /// Whole seconds only: keeps JSON round-trips equal and dates tidy in the UI.
    static func normalized(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded())
    }

    public var watchURL: URL { YouTubeURL.watchURL(for: youtubeID) }
    public var thumbnailURL: URL { YouTubeURL.thumbnailURL(for: youtubeID) }

    public var durationLabel: String {
        guard let seconds = durationSeconds, seconds > 0 else { return "" }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    public var addedLabel: String {
        addedAt.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// Full moment, with the zone it is being shown in. The stored value is an
    /// instant; the zone is a presentation choice, so a shelf opened in another
    /// country still reads correctly.
    public func addedTimestamp(
        timeZone: TimeZone = .current,
        locale: Locale = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "d MMM yyyy, HH:mm zzz"
        return formatter.string(from: addedAt)
    }

    /// Text used for search and for the keyword fallback tagger.
    public var searchCorpus: String {
        ([title, channel, note] + tags).joined(separator: " ")
    }
}
