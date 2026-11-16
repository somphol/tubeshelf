import Foundation

/// The parts of a shelf a backup can change. Used as the common ancestor for a
/// three-way merge and as the payload of a merge review.
public struct ShelfSnapshot: Codable, Equatable, Sendable {
    public var library: Library
    public var playlists: [PlaylistRecord]

    public init(library: Library, playlists: [PlaylistRecord] = []) {
        self.library = library
        self.playlists = playlists
    }
}

/// The last state the Mac could share with the web: written after a successful
/// backup and after a restore, never after an ordinary edit.
public struct MergeBaseStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent("merge-base.json") }

    public func load() -> ShelfSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ShelfSnapshot.self, from: data)
    }

    public func save(_ snapshot: ShelfSnapshot) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

public enum MergeChoice: String, Codable, Sendable {
    case mine
    case theirs
    case both
}

public enum MergeField: String, CaseIterable, Hashable, Sendable {
    case tags
    case note
    case isFavorite
    case watchStatus

    public var label: String {
        switch self {
        case .tags: "Categories"
        case .note: "Note"
        case .isFavorite: "Favorite"
        case .watchStatus: "Watch state"
        }
    }

    public var allowsBoth: Bool { self == .tags }

    public var defaultChoice: MergeChoice { allowsBoth ? .both : .mine }
}

public enum MergeValue: Equatable, Sendable {
    case tags([String])
    case text(String)
    case flag(Bool)
    case status(WatchStatus)

    public var displayText: String {
        switch self {
        case .tags(let tags):
            tags.isEmpty ? "No categories" : tags.joined(separator: ", ")
        case .text(let text):
            text.isEmpty ? "Empty" : text
        case .flag(let flag):
            flag ? "Favorite" : "Not favorite"
        case .status(let status):
            status.label
        }
    }
}

public struct MergeFieldConflict: Identifiable, Sendable {
    public var field: MergeField
    public var mine: MergeValue
    public var theirs: MergeValue
    public var both: MergeValue?
    public var defaultChoice: MergeChoice

    public var id: MergeField { field }
}

public struct MergeConflict: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case video
        case playlist
    }

    public enum Presence: String, Sendable {
        case altered
        case deletedInBackup
        case deletedHere
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var fields: [MergeFieldConflict]
    public var presence: Presence?
    public var incomingVideo: Video?
    public var incomingPlaylist: PlaylistRecord?
    public var mineTitle: String?
    public var theirsTitle: String?
    public var defaultChoice: MergeChoice

    public var presenceKey: String { "\(kind.rawValue):\(id):presence" }

    public func choiceKey(for field: MergeFieldConflict) -> String {
        "\(kind.rawValue):\(id):\(field.field.rawValue)"
    }
}

public struct MergeStats: Equatable, Sendable {
    public var added = 0
    public var updated = 0
    public var deleted = 0
    public var kept = 0

    public init(added: Int = 0, updated: Int = 0, deleted: Int = 0, kept: Int = 0) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.kept = kept
    }

    public var changes: Int { added + updated + deleted }
}

public struct ShelfMergeResult: Sendable {
    public var snapshot: ShelfSnapshot
    public var conflicts: [MergeConflict]
    public var stats: MergeStats
}

/// Three-way shelf merge. One-sided changes apply automatically; only fields
/// changed differently on both sides become conflicts.
public enum ShelfMerger {
    public static func merge(
        base: ShelfSnapshot?,
        mine: ShelfSnapshot,
        theirs: ShelfSnapshot
    ) -> ShelfMergeResult {
        var conflicts: [MergeConflict] = []
        var stats = MergeStats()

        let baseVideos = dictionary(base?.library.videos ?? [], key: \.youtubeID)
        let theirVideos = dictionary(theirs.library.videos, key: \.youtubeID)
        var videos: [Video] = []
        var seenVideos = Set<String>()

        for current in mine.library.videos {
            guard !seenVideos.contains(current.youtubeID) else { continue }
            seenVideos.insert(current.youtubeID)
            let original = baseVideos[current.youtubeID]
            let incoming = theirVideos[current.youtubeID]

            if let incoming {
                let result = mergeVideo(base: original, mine: current, theirs: incoming)
                videos.append(result.video)
                if !result.fields.isEmpty {
                    conflicts.append(MergeConflict(
                        id: current.youtubeID,
                        kind: .video,
                        title: result.video.title,
                        fields: result.fields,
                        presence: nil,
                        incomingVideo: nil,
                        incomingPlaylist: nil,
                        mineTitle: nil,
                        theirsTitle: nil,
                        defaultChoice: .mine
                    ))
                }
                if result.updated { stats.updated += 1 }
            } else if original == nil {
                videos.append(current)
                stats.kept += 1
            } else if sameValues(VideoValues(original!), VideoValues(current)) {
                stats.deleted += 1
            } else {
                videos.append(current)
                conflicts.append(videoPresence(.deletedInBackup, mine: current, theirs: nil))
            }
        }

        for incoming in theirs.library.videos {
            guard !seenVideos.contains(incoming.youtubeID) else { continue }
            seenVideos.insert(incoming.youtubeID)
            let original = baseVideos[incoming.youtubeID]
            if original == nil {
                videos.append(incoming)
                stats.added += 1
            } else if !sameValues(VideoValues(original!), VideoValues(incoming)) {
                conflicts.append(videoPresence(.deletedHere, mine: nil, theirs: incoming))
            }
        }

        // A backup with no catalog is treated as "no playlist information",
        // never as "delete every course".
        let incomingCatalog = theirs.playlists.isEmpty ? nil : theirs.playlists
        let basePlaylists = dictionary(base?.playlists ?? [], key: \.id)
        let theirPlaylists = dictionary(incomingCatalog ?? [], key: \.id)
        var playlists: [PlaylistRecord] = []
        var seenPlaylists = Set<String>()

        for current in mine.playlists {
            guard !seenPlaylists.contains(current.id) else { continue }
            seenPlaylists.insert(current.id)
            guard incomingCatalog != nil else {
                playlists.append(current)
                continue
            }
            let original = basePlaylists[current.id]
            let incoming = theirPlaylists[current.id]

            if let incoming {
                if samePlaylist(current, incoming) {
                    playlists.append(current)
                } else if original == nil {
                    playlists.append(current)
                    conflicts.append(playlistConflict(.altered, mine: current, theirs: incoming))
                } else if samePlaylist(original!, current) {
                    playlists.append(incoming)
                    stats.updated += 1
                } else if samePlaylist(original!, incoming) {
                    playlists.append(current)
                } else {
                    playlists.append(current)
                    conflicts.append(playlistConflict(.altered, mine: current, theirs: incoming))
                }
            } else if original == nil {
                playlists.append(current)
                stats.kept += 1
            } else if samePlaylist(original!, current) {
                stats.deleted += 1
            } else {
                playlists.append(current)
                conflicts.append(playlistConflict(.deletedInBackup, mine: current, theirs: nil))
            }
        }

        if let incomingCatalog {
            for incoming in incomingCatalog {
                guard !seenPlaylists.contains(incoming.id) else { continue }
                seenPlaylists.insert(incoming.id)
                let original = basePlaylists[incoming.id]
                if original == nil {
                    playlists.append(incoming)
                    stats.added += 1
                } else if !samePlaylist(original!, incoming) {
                    conflicts.append(playlistConflict(.deletedHere, mine: nil, theirs: incoming))
                }
            }
        }

        let mergedLibrary = Library(
            videos: videos,
            pinnedTags: mergeNames(
                base: base?.library.pinnedTags,
                mine: mine.library.pinnedTags,
                theirs: theirs.library.pinnedTags,
                asTags: true
            ),
            pinnedChannels: mergeNames(
                base: base?.library.pinnedChannels,
                mine: mine.library.pinnedChannels,
                theirs: theirs.library.pinnedChannels,
                asTags: false
            )
        )

        return ShelfMergeResult(
            snapshot: ShelfSnapshot(library: mergedLibrary, playlists: playlists),
            conflicts: conflicts,
            stats: stats
        )
    }

    public static func resolve(
        _ result: ShelfMergeResult,
        choices: [String: MergeChoice]
    ) -> ShelfSnapshot {
        var videos = result.snapshot.library.videos
        var playlists = result.snapshot.playlists

        for conflict in result.conflicts {
            if !conflict.fields.isEmpty {
                guard let index = videos.firstIndex(where: { $0.youtubeID == conflict.id }) else { continue }
                for field in conflict.fields {
                    let choice = choices[conflict.choiceKey(for: field)] ?? field.defaultChoice
                    let value: MergeValue
                    switch choice {
                    case .mine: value = field.mine
                    case .theirs: value = field.theirs
                    case .both: value = field.both ?? field.mine
                    }
                    switch field.field {
                    case .tags:
                        if case .tags(let tags) = value { videos[index].tags = TagNormalizer.merge(tags) }
                    case .note:
                        if case .text(let text) = value { videos[index].note = text }
                    case .isFavorite:
                        if case .flag(let flag) = value { videos[index].isFavorite = flag }
                    case .watchStatus:
                        if case .status(let status) = value { videos[index].watchStatus = status }
                    }
                }
                continue
            }

            let choice = choices[conflict.presenceKey] ?? conflict.defaultChoice
            switch conflict.presence {
            case .deletedInBackup:
                if choice == .theirs {
                    if conflict.kind == .video {
                        videos.removeAll { $0.youtubeID == conflict.id }
                    } else {
                        playlists.removeAll { $0.id == conflict.id }
                    }
                }
            case .deletedHere:
                if choice == .theirs {
                    if conflict.kind == .video, let incoming = conflict.incomingVideo,
                       !videos.contains(where: { $0.youtubeID == incoming.youtubeID }) {
                        videos.append(incoming)
                    } else if conflict.kind == .playlist, let incoming = conflict.incomingPlaylist,
                              !playlists.contains(where: { $0.id == incoming.id }) {
                        playlists.append(incoming)
                    }
                }
            case .altered:
                if choice == .theirs, let incoming = conflict.incomingPlaylist,
                   let index = playlists.firstIndex(where: { $0.id == incoming.id }) {
                    playlists[index] = incoming
                }
            case .none:
                break
            }
        }

        return ShelfSnapshot(
            library: Library(
                videos: videos,
                pinnedTags: result.snapshot.library.pinnedTags,
                pinnedChannels: result.snapshot.library.pinnedChannels
            ),
            playlists: playlists
        )
    }

    // MARK: - Videos

    private struct VideoValues {
        var tags: [String]
        var note: String
        var isFavorite: Bool
        var watchStatus: WatchStatus

        init(_ video: Video) {
            self.tags = TagNormalizer.merge(video.tags)
            self.note = video.note
            self.isFavorite = video.isFavorite
            self.watchStatus = video.watchStatus
        }

        func value(_ field: MergeField) -> MergeValue {
            switch field {
            case .tags: .tags(tags)
            case .note: .text(note)
            case .isFavorite: .flag(isFavorite)
            case .watchStatus: .status(watchStatus)
            }
        }

        func same(_ field: MergeField, _ other: VideoValues) -> Bool {
            switch field {
            case .tags: sameTags(tags, other.tags)
            case .note: note == other.note
            case .isFavorite: isFavorite == other.isFavorite
            case .watchStatus: watchStatus == other.watchStatus
            }
        }
    }

    private static func mergeVideo(
        base: Video?,
        mine: Video,
        theirs: Video
    ) -> (video: Video, fields: [MergeFieldConflict], updated: Bool) {
        let baseValues = base.map(VideoValues.init)
        let mineValues = VideoValues(mine)
        let theirValues = VideoValues(theirs)
        var merged = mine
        var fields: [MergeFieldConflict] = []
        var updated = false

        for field in MergeField.allCases {
            let mineValue = mineValues.value(field)
            let theirValue = theirValues.value(field)
            if mineValues.same(field, theirValues) { continue }

            if let baseValues {
                if baseValues.same(field, mineValues) {
                    apply(theirValue, field: field, to: &merged)
                    updated = true
                    continue
                }
                if baseValues.same(field, theirValues) { continue }
            }

            let both: MergeValue? = field == .tags
                ? .tags(mergeTagSets(base: baseValues?.tags ?? [], mine: mineValues.tags, theirs: theirValues.tags))
                : nil
            let conflict = MergeFieldConflict(
                field: field,
                mine: mineValue,
                theirs: theirValue,
                both: both,
                defaultChoice: field.defaultChoice
            )
            fields.append(conflict)
            switch field.defaultChoice {
            case .both: if let both { apply(both, field: field, to: &merged) }
            case .mine: apply(mineValue, field: field, to: &merged)
            case .theirs: apply(theirValue, field: field, to: &merged)
            }
        }

        let title = pick(base?.title, mine.title, theirs.title)
        let channel = pick(base?.channel, mine.channel, theirs.channel)
        let duration = pickDuration(base?.durationSeconds, mine.durationSeconds, theirs.durationSeconds)
        merged.title = title.isEmpty ? (mine.title.isEmpty ? "Untitled" : mine.title) : title
        merged.channel = channel
        merged.durationSeconds = duration
        if merged.title != mine.title || merged.channel != mine.channel || merged.durationSeconds != mine.durationSeconds {
            updated = true
        }
        return (merged, fields, updated)
    }

    private static func apply(_ value: MergeValue, field: MergeField, to video: inout Video) {
        switch (field, value) {
        case (.tags, .tags(let tags)): video.tags = TagNormalizer.merge(tags)
        case (.note, .text(let text)): video.note = text
        case (.isFavorite, .flag(let flag)): video.isFavorite = flag
        case (.watchStatus, .status(let status)): video.watchStatus = status
        default: break
        }
    }

    private static func pick(_ base: String?, _ mine: String, _ theirs: String) -> String {
        if mine == theirs { return mine }
        if let base, base == mine { return theirs }
        if let base, base == theirs { return mine }
        return mine.isEmpty ? theirs : mine
    }

    private static func pickDuration(_ base: Int?, _ mine: Int?, _ theirs: Int?) -> Int? {
        if mine == theirs { return mine }
        if mine == nil { return theirs }
        if theirs == nil { return mine }
        if let base, base == mine { return theirs }
        if let base, base == theirs { return mine }
        return theirs
    }

    private static func sameValues(_ mine: VideoValues, _ theirs: VideoValues) -> Bool {
        MergeField.allCases.allSatisfy { mine.same($0, theirs) }
    }

    private static func sameTags(_ mine: [String], _ theirs: [String]) -> Bool {
        Set(mine.map { $0.lowercased() }) == Set(theirs.map { $0.lowercased() })
    }

    private static func mergeTagSets(base: [String], mine: [String], theirs: [String]) -> [String] {
        let baseKeys = Set(base.map { $0.lowercased() })
        let mineKeys = Set(mine.map { $0.lowercased() })
        let theirKeys = Set(theirs.map { $0.lowercased() })
        var seen = Set<String>()
        var out: [String] = []

        for tag in mine + theirs {
            let key = tag.lowercased()
            guard seen.insert(key).inserted else { continue }
            let inBase = baseKeys.contains(key)
            let inMine = mineKeys.contains(key)
            let inTheirs = theirKeys.contains(key)
            let keep: Bool
            if inMine == inTheirs {
                keep = inMine
            } else if inMine == inBase {
                keep = inTheirs
            } else if inTheirs == inBase {
                keep = inMine
            } else {
                keep = true
            }
            if keep {
                out.append(inMine ? mine.first { $0.lowercased() == key }! : theirs.first { $0.lowercased() == key }!)
            }
        }
        return TagNormalizer.merge(out)
    }

    private static func videoPresence(
        _ presence: MergeConflict.Presence,
        mine: Video?,
        theirs: Video?
    ) -> MergeConflict {
        let source = mine ?? theirs!
        return MergeConflict(
            id: source.youtubeID,
            kind: .video,
            title: source.title.isEmpty ? "(untitled)" : source.title,
            fields: [],
            presence: presence,
            incomingVideo: theirs,
            incomingPlaylist: nil,
            mineTitle: nil,
            theirsTitle: nil,
            defaultChoice: .mine
        )
    }

    // MARK: - Playlists

    private struct PlaylistSignature: Equatable {
        var title: String
        var channel: String
        var tags: [String]
        var items: [PlaylistItem]
        var watched: [String]
        var truncated: Bool

        init(_ playlist: PlaylistRecord) {
            self.title = playlist.title
            self.channel = playlist.channel
            self.tags = playlist.tags.map { $0.lowercased() }.sorted()
            self.items = playlist.items
            self.watched = playlist.watchedItemIDs.map { $0.lowercased() }.sorted()
            self.truncated = playlist.isTruncated
        }
    }

    private static func samePlaylist(_ mine: PlaylistRecord, _ theirs: PlaylistRecord) -> Bool {
        PlaylistSignature(mine) == PlaylistSignature(theirs)
    }

    private static func playlistConflict(
        _ presence: MergeConflict.Presence,
        mine: PlaylistRecord?,
        theirs: PlaylistRecord?
    ) -> MergeConflict {
        let source = mine ?? theirs!
        return MergeConflict(
            id: source.id,
            kind: .playlist,
            title: source.title.isEmpty ? "(untitled course)" : source.title,
            fields: [],
            presence: presence,
            incomingVideo: nil,
            incomingPlaylist: theirs,
            mineTitle: mine?.title,
            theirsTitle: theirs?.title,
            defaultChoice: .mine
        )
    }

    // MARK: - Pins

    private static func mergeNames(
        base: [String]?,
        mine: [String],
        theirs: [String],
        asTags: Bool
    ) -> [String] {
        let baseKeys = Set((base ?? []).map { $0.lowercased() })
        let mineKeys = Set(mine.map { $0.lowercased() })
        let theirKeys = Set(theirs.map { $0.lowercased() })
        var seen = Set<String>()
        var out: [String] = []

        for name in mine + theirs {
            let key = name.lowercased()
            guard seen.insert(key).inserted else { continue }
            let inMine = mineKeys.contains(key)
            let inTheirs = theirKeys.contains(key)
            let inBase = baseKeys.contains(key)
            let keep: Bool
            if inMine == inTheirs {
                keep = inMine
            } else if base == nil {
                keep = true
            } else if inMine == inBase {
                keep = inTheirs
            } else if inTheirs == inBase {
                keep = inMine
            } else {
                keep = true
            }
            if keep {
                out.append(inMine ? mine.first { $0.lowercased() == key }! : theirs.first { $0.lowercased() == key }!)
            }
        }
        return asTags ? TagNormalizer.merge(out) : out
    }

    private static func dictionary<T>(_ items: [T], key: KeyPath<T, String>) -> [String: T] {
        var result: [String: T] = [:]
        for item in items {
            let id = item[keyPath: key]
            if result[id] == nil { result[id] = item }
        }
        return result
    }
}
