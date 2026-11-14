import Foundation

public enum ShelfFilter: Hashable, Sendable, Codable {
    case all
    case favorites
    case unsorted
    case tag(String)
    case channel(String)

    public var title: String {
        switch self {
        case .all: "All videos"
        case .favorites: "Favorites"
        case .unsorted: "Unsorted"
        case .tag(let name): name
        case .channel(let name): name
        }
    }

    public var tagName: String? {
        if case .tag(let name) = self { return name }
        return nil
    }

    public var channelName: String? {
        if case .channel(let name) = self { return name }
        return nil
    }
}

public struct TagCount: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

/// How the category browser orders its rows.
public enum CategorySort: String, CaseIterable, Codable, Sendable {
    case mostVideos
    case name

    public var label: String {
        switch self {
        case .mostVideos: "Video count"
        case .name: "Name"
        }
    }
}

/// How wide the text search reaches. "Titles" is the fast, precise mode; 
/// "Everything" also covers channel, note and categories.
public enum SearchScope: String, CaseIterable, Codable, Sendable {
    case everything
    case titles

    public var label: String {
        switch self {
        case .everything: "Everything"
        case .titles: "Titles"
        }
    }
}

public struct Library: Codable, Equatable, Sendable {
    public private(set) var videos: [Video]
    /// Category names pinned to the top of the sidebar, in pin order.
    public private(set) var pinnedTags: [String]

    public init(videos: [Video] = [], pinnedTags: [String] = []) {
        self.videos = videos
        self.pinnedTags = TagNormalizer.merge(pinnedTags)
        prunePinnedTags()
    }

    private enum CodingKeys: String, CodingKey {
        case videos
        case pinnedTags
    }

    // Older library files have no `pinnedTags` key; they still open.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.videos = try container.decodeIfPresent([Video].self, forKey: .videos) ?? []
        self.pinnedTags = TagNormalizer.merge(
            try container.decodeIfPresent([String].self, forKey: .pinnedTags) ?? []
        )
        prunePinnedTags()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(videos, forKey: .videos)
        try container.encode(pinnedTags, forKey: .pinnedTags)
    }

    public var isEmpty: Bool { videos.isEmpty }
    public var count: Int { videos.count }

    public func video(id: UUID) -> Video? {
        videos.first { $0.id == id }
    }

    public func video(youtubeID: String) -> Video? {
        videos.first { $0.youtubeID == youtubeID }
    }

    public func contains(youtubeID: String) -> Bool {
        videos.contains { $0.youtubeID == youtubeID }
    }

    /// Returns false when the video is already on the shelf, so callers can offer
    /// "show me the existing one" instead of duplicating it.
    @discardableResult
    public mutating func add(_ video: Video) -> Bool {
        guard !contains(youtubeID: video.youtubeID) else { return false }
        videos.append(video)
        return true
    }

    public mutating func update(_ video: Video) {
        guard let index = videos.firstIndex(where: { $0.id == video.id }) else { return }
        videos[index] = video
    }

    public mutating func remove(id: UUID) {
        videos.removeAll { $0.id == id }
    }

    public mutating func remove(youtubeID: String) {
        videos.removeAll { $0.youtubeID == youtubeID }
    }

    public mutating func toggleFavorite(id: UUID) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].isFavorite.toggle()
    }

    public mutating func setTags(_ tags: [String], for id: UUID) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].tags = TagNormalizer.merge(tags)
    }

    public mutating func setNote(_ note: String, for id: UUID) {
        guard let index = videos.firstIndex(where: { $0.id == id }) else { return }
        videos[index].note = note
    }

    /// Renames a category everywhere. If the target already exists on a video,
    /// the duplicate is dropped rather than duplicated. A pinned category stays
    /// pinned under its new name.
    public mutating func renameTag(_ old: String, to new: String) {
        guard let cleaned = TagNormalizer.canonical(new) else { return }
        guard cleaned.caseInsensitiveCompare(old) != .orderedSame else { return }
        let wasPinned = isPinned(old)
        mergeTagsWithoutPinMaintenance(old, into: cleaned)
        if wasPinned {
            pin(cleaned)
            unpin(old)
        }
    }

    public mutating func deleteTag(_ name: String) {
        for index in videos.indices {
            videos[index].tags.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        unpin(name)
    }

    /// Collapses two categories into one. Returns how many videos moved.
    /// If the source was pinned and the destination was not, the destination
    /// inherits the pin so the person does not lose their spot on the shelf.
    @discardableResult
    public mutating func mergeTags(_ source: String, into destination: String) -> Int {
        guard let cleaned = TagNormalizer.canonical(destination) else { return 0 }
        guard cleaned.caseInsensitiveCompare(source) != .orderedSame else { return 0 }
        let moved = mergeTagsWithoutPinMaintenance(source, into: cleaned)
        if isPinned(source) {
            pin(cleaned)
            unpin(source)
        }
        return moved
    }

    private mutating func mergeTagsWithoutPinMaintenance(_ source: String, into destination: String) -> Int {
        var moved = 0
        for index in videos.indices {
            let hitsSource = videos[index].tags.contains { $0.caseInsensitiveCompare(source) == .orderedSame }
            guard hitsSource else { continue }
            let remaining = videos[index].tags.filter { $0.caseInsensitiveCompare(source) != .orderedSame }
            videos[index].tags = TagNormalizer.merge(remaining + [destination])
            moved += 1
        }
        return moved
    }

    // MARK: - Pinning

    public func isPinned(_ tag: String) -> Bool {
        pinnedTags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    public mutating func pin(_ tag: String) {
        guard let cleaned = TagNormalizer.canonical(tag), !isPinned(cleaned) else { return }
        pinnedTags.append(cleaned)
    }

    public mutating func unpin(_ tag: String) {
        pinnedTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
    }

    /// Returns the new pinned state.
    @discardableResult
    public mutating func togglePin(_ tag: String) -> Bool {
        if isPinned(tag) {
            unpin(tag)
            return false
        }
        pin(tag)
        return true
    }

    public mutating func unpinAll() {
        pinnedTags.removeAll()
    }

    /// Drops pins whose category no longer exists on any video.
    public mutating func prunePinnedTags() {
        let existing = Set(tagCounts.map { $0.name.lowercased() })
        pinnedTags.removeAll { !existing.contains($0.lowercased()) }
    }

    public var tagCounts: [TagCount] {
        let counts = rawTagCounts()
        return Self.sort(counts, by: .mostVideos, ascending: false)
    }

    /// Every category, ordered the way the browser asked for.
    public func tagCounts(sortedBy sort: CategorySort, ascending: Bool = false) -> [TagCount] {
        Self.sort(rawTagCounts(), by: sort, ascending: ascending)
    }

    /// Pinned categories in the order they were pinned, skipping any that no
    /// longer have videos.
    public var pinnedTagCounts: [TagCount] {
        let counts = rawTagCounts()
        return pinnedTags.compactMap { pin in
            counts.first { $0.name.caseInsensitiveCompare(pin) == .orderedSame }
        }
    }

    public func unpinnedTagCounts(sortedBy sort: CategorySort, ascending: Bool = false) -> [TagCount] {
        let pinnedKeys = Set(pinnedTags.map { $0.lowercased() })
        let rest = rawTagCounts().filter { !pinnedKeys.contains($0.name.lowercased()) }
        return Self.sort(rest, by: sort, ascending: ascending)
    }

    private func rawTagCounts() -> [TagCount] {
        var tally: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for video in videos {
            for tag in video.tags {
                let key = tag.lowercased()
                tally[key, default: 0] += 1
                spelling[key] = spelling[key] ?? tag
            }
        }
        return tally.map { TagCount(name: spelling[$0.key] ?? $0.key, count: $0.value) }
    }

    private static func sort(_ counts: [TagCount], by sort: CategorySort, ascending: Bool) -> [TagCount] {
        counts.sorted { lhs, rhs in
            switch sort {
            case .mostVideos:
                if lhs.count != rhs.count {
                    return ascending ? lhs.count < rhs.count : lhs.count > rhs.count
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .name:
                let isAscending = lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                return ascending ? isAscending : !isAscending
            }
        }
    }

    public var allTags: [String] { tagCounts.map(\.name) }

    // MARK: - Channels

    /// Every channel on the shelf, most prolific first by default.
    public func channelCounts(sortedBy sort: CategorySort = .mostVideos, ascending: Bool = false) -> [TagCount] {
        var tally: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for video in videos {
            let name = video.channel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            tally[key, default: 0] += 1
            spelling[key] = spelling[key] ?? name
        }
        let counts = tally.map { TagCount(name: spelling[$0.key] ?? $0.key, count: $0.value) }
        return Self.sort(counts, by: sort, ascending: ascending)
    }

    /// The category a channel is usually filed under, if the pattern is strong
    /// enough to be worth using as a fallback for a video with no clear signal.
    public func channelAffinity(
        for channel: String,
        minimumVideos: Int = 3,
        share: Double = 0.6
    ) -> String? {
        let name = channel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let channelVideos = videos.filter { $0.channel.caseInsensitiveCompare(name) == .orderedSame }
        guard channelVideos.count >= minimumVideos else { return nil }

        var tally: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for video in channelVideos {
            for tag in video.tags {
                let key = tag.lowercased()
                tally[key, default: 0] += 1
                spelling[key] = spelling[key] ?? tag
            }
        }

        // Two of three videos in one category is a pattern; one of three is a
        // coincidence. The share check does the real work here.
        guard let best = tally.max(by: { $0.value < $1.value }),
              best.value >= max(2, minimumVideos - 1),
              Double(best.value) / Double(channelVideos.count) >= share
        else { return nil }

        return spelling[best.key]
    }

    public var favoritesCount: Int { videos.filter(\.isFavorite).count }
    public var unsortedCount: Int { videos.filter(\.tags.isEmpty).count }

    /// Category filter first, then text search. Newest saved first.
    public func videos(
        filter: ShelfFilter,
        query: String = "",
        scope: SearchScope = .everything
    ) -> [Video] {
        let filtered = videos.filter { video in
            switch filter {
            case .all:
                return true
            case .favorites:
                return video.isFavorite
            case .unsorted:
                return video.tags.isEmpty
            case .tag(let name):
                return video.tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            case .channel(let name):
                return video.channel.caseInsensitiveCompare(name) == .orderedSame
            }
        }

        let needle = SearchText.normalize(query)
        let matches = needle.isEmpty ? filtered : filtered.filter { video in
            switch scope {
            case .everything:
                return SearchText.matches(needle: needle, haystack: video.searchCorpus)
            case .titles:
                return SearchText.matches(needle: needle, haystack: video.title)
            }
        }

        return matches.sorted { $0.addedAt > $1.addedAt }
    }
}

public enum SearchText {
    public static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    /// Every whitespace-separated term must appear somewhere in the corpus, so
    /// "swift actor" matches "Actors in Swift" but "rust actor" does not.
    public static func matches(needle: String, haystack: String) -> Bool {
        let normalizedHaystack = normalize(haystack)
        return needle
            .split(separator: " ")
            .allSatisfy { normalizedHaystack.contains(String($0)) }
    }
}
