import Foundation

/// A public playlist kept as a course: ordered chapters, whether or not those
/// videos are on the shelf. Deleting it never touches videos, and deleting a
/// video never breaks it.
public struct PlaylistRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var channel: String
    public var items: [PlaylistItem]
    public var addedAt: Date
    public var fetchedAt: Date
    /// Chapters ticked off inside this playlist. Independent of the shelf's watch
    /// state, so a course can be tracked without filing every video.
    public var watchedItemIDs: [String]
    public var isTruncated: Bool
    /// Categories for the course itself, so it can sit beside videos in a category.
    public var tags: [String]

    public init(
        id: String,
        title: String,
        channel: String,
        items: [PlaylistItem],
        addedAt: Date = Date(),
        fetchedAt: Date = Date(),
        watchedItemIDs: [String] = [],
        isTruncated: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.title = title
        self.channel = channel
        self.items = items
        self.addedAt = Video.normalized(addedAt)
        self.fetchedAt = Video.normalized(fetchedAt)
        self.watchedItemIDs = watchedItemIDs
        self.isTruncated = isTruncated
        self.tags = TagNormalizer.merge(tags)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, channel, items, addedAt, fetchedAt, watchedItemIDs, isTruncated, tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Playlist"
        channel = try container.decodeIfPresent(String.self, forKey: .channel) ?? ""
        items = try container.decodeIfPresent([PlaylistItem].self, forKey: .items) ?? []
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        fetchedAt = try container.decodeIfPresent(Date.self, forKey: .fetchedAt) ?? addedAt
        watchedItemIDs = try container.decodeIfPresent([String].self, forKey: .watchedItemIDs) ?? []
        isTruncated = try container.decodeIfPresent(Bool.self, forKey: .isTruncated) ?? false
        tags = TagNormalizer.merge(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
    }

    public var chapterCount: Int { items.count }
    public var watchedCount: Int {
        items.filter { isWatched($0.videoID) }.count
    }
    public var progress: Double {
        chapterCount == 0 ? 0 : Double(watchedCount) / Double(chapterCount)
    }
    public var coverVideoID: String? { items.first?.videoID }
    public var shareURL: URL? {
        URL(string: "https://www.youtube.com/playlist?list=\(id)")
    }

    public func hasTag(_ tag: String) -> Bool {
        tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public func isWatched(_ videoID: String) -> Bool {
        watchedItemIDs.contains { $0.caseInsensitiveCompare(videoID) == .orderedSame }
    }

    public mutating func setWatched(_ watched: Bool, videoID: String) {
        watchedItemIDs.removeAll { $0.caseInsensitiveCompare(videoID) == .orderedSame }
        if watched { watchedItemIDs.append(videoID) }
    }

    /// Refreshing keeps the ticks that still correspond to a chapter.
    public mutating func replaceItems(_ newItems: [PlaylistItem], fetchedAt: Date = Date()) {
        let known = Set(newItems.map { $0.videoID.lowercased() })
        items = newItems
        watchedItemIDs = watchedItemIDs.filter { known.contains($0.lowercased()) }
        self.fetchedAt = Video.normalized(fetchedAt)
    }
}

/// One file per profile: `playlists.json`.
public struct PlaylistStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent("playlists.json") }

    private struct Envelope: Codable {
        var playlists: [PlaylistRecord]
    }

    public func load() throws -> [PlaylistRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Envelope.self, from: data).playlists
                .sorted { $0.addedAt > $1.addedAt }
        } catch {
            // Never overwrite a file we failed to read.
            let backup = directory.appendingPathComponent(
                "playlists-corrupt-\(Int(Date().timeIntervalSince1970)).json"
            )
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
    }

    public func save(_ records: [PlaylistRecord]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(Envelope(playlists: records))
        try data.write(to: fileURL, options: .atomic)
    }
}
