import Foundation
import Darwin
import TubeShelfCore

/// Headless verification + small maintenance CLI for TubeShelf.
///
///   tubeshelf-check                 offline checks
///   tubeshelf-check --probe         on-device model status and live suggestions
///   tubeshelf-check --fetch <link>  metadata + suggestions for one video
///   tubeshelf-check --seed-demo     add the example shelf
///   tubeshelf-check --reset         empty the library
@main
struct TubeShelfCheck {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())

        if arguments.contains("--help") || arguments.contains("-h") {
            printUsage()
            return
        }

        // Profiles moved the real shelf into Profiles/<uuid>/. The CLI must act on
        // the same shelf the app is using, not the pre-profile file at the root.
        let store = activeStore()

        do {
            if arguments.contains("--seed-demo") {
                try seedDemo(store: store)
                return
            }
            if arguments.contains("--reset") {
                try store.save(Library())
                print("Library emptied: \(store.fileURL.path)")
                return
            }
            if let index = arguments.firstIndex(of: "--fetch"), index + 1 < arguments.count {
                let ok = await fetchOne(arguments[index + 1])
                exit(ok ? 0 : 1)
            }
            if let index = arguments.firstIndex(of: "--playlist"), index + 1 < arguments.count {
                let ok = await fetchPlaylist(arguments[index + 1])
                exit(ok ? 0 : 1)
            }
            if let index = arguments.firstIndex(of: "--backup"), index + 1 < arguments.count {
                let library = try store.load()
                let playlists = (try? PlaylistStore(directory: store.directory).load()) ?? []
                let url = URL(fileURLWithPath: arguments[index + 1])
                try BackupService().write(library, playlists: playlists, to: url)
                try? MergeBaseStore(directory: store.directory)
                    .save(ShelfSnapshot(library: library, playlists: playlists))
                print("Backed up \(library.count) videos and \(playlists.count) playlists → \(url.path)")
                return
            }
            if let index = arguments.firstIndex(of: "--restore"), index + 1 < arguments.count {
                let url = URL(fileURLWithPath: arguments[index + 1])
                let contents = try BackupService().readContents(from: url)
                let stamp = Int(Date().timeIntervalSince1970)
                if let data = try? Data(contentsOf: store.fileURL) {
                    try? data.write(
                        to: store.directory.appendingPathComponent("library-before-restore-\(stamp).json"),
                        options: .atomic
                    )
                }
                let playlistStore = PlaylistStore(directory: store.directory)
                if let data = try? Data(contentsOf: playlistStore.fileURL) {
                    try? data.write(
                        to: store.directory.appendingPathComponent("playlists-before-restore-\(stamp).json"),
                        options: .atomic
                    )
                }
                try store.save(contents.library)
                try playlistStore.save(contents.playlists)
                try? MergeBaseStore(directory: store.directory)
                    .save(ShelfSnapshot(library: contents.library, playlists: contents.playlists))
                print("Restored \(contents.library.count) videos and \(contents.playlists.count) playlists ← \(url.path)")
                return
            }
            if let index = arguments.firstIndex(of: "--pin"), index + 1 < arguments.count {
                var library = try store.load()
                library.pin(arguments[index + 1])
                try store.save(library)
                print("Pinned \(arguments[index + 1]). Pinned now: \(library.pinnedTags.joined(separator: ", "))")
                return
            }
            if let index = arguments.firstIndex(of: "--unpin"), index + 1 < arguments.count {
                var library = try store.load()
                library.unpin(arguments[index + 1])
                try store.save(library)
                print("Unpinned \(arguments[index + 1]). Pinned now: \(library.pinnedTags.joined(separator: ", "))")
                return
            }
            if let index = arguments.firstIndex(of: "--merge"), index + 2 < arguments.count {
                var library = try store.load()
                let moved = library.mergeTags(arguments[index + 1], into: arguments[index + 2])
                try store.save(library)
                print("Merged \(arguments[index + 1]) into \(arguments[index + 2]): \(moved) videos moved.")
                return
            }

            let checker = Checker()
            try runOfflineChecks(checker: checker)

            if arguments.contains("--probe") {
                await probeModel()
            }

            checker.report()
            exit(checker.failures.isEmpty ? 0 : 1)
        } catch {
            print("error: \(error)")
            exit(1)
        }
    }

    static func printUsage() {
        print("""
        tubeshelf-check — headless checks for TubeShelf

          (no flags)        offline checks: links, tagging, shelf, deck, disk
          --probe           on-device model status + live tag suggestions
          --fetch <link>    metadata and suggestions for one video
          --playlist <link> list the videos in a playlist
          --seed-demo       add the seven example videos
          --reset           empty the library
          --backup <path>        write a versioned backup file
          --restore <path>       replace the shelf from a backup (keeps a copy)
          --pin <category>       pin a category to the sidebar
          --unpin <category>     remove a pin
          --merge <from> <into>  collapse two categories
        """)
    }

    /// The profile the app is currently using, falling back to the largest one.
    static func activeStore() -> LibraryStore {
        let profileStore = ProfileStore()
        guard let profiles = try? profileStore.profiles(), !profiles.isEmpty else {
            return LibraryStore()
        }

        let saved = UserDefaults(suiteName: "studio.somphol.tubeshelf")?
            .string(forKey: "activeProfileID")
            .flatMap(UUID.init(uuidString:))
        if let match = profiles.first(where: { $0.id == saved }) {
            return profileStore.libraryStore(for: match)
        }

        let largest = profiles.max { lhs, rhs in
            let left = (try? profileStore.libraryStore(for: lhs).load().count) ?? 0
            let right = (try? profileStore.libraryStore(for: rhs).load().count) ?? 0
            return left < right
        }
        return largest.map { profileStore.libraryStore(for: $0) } ?? LibraryStore()
    }

    // MARK: - Offline checks

    @MainActor
    static func runOfflineChecks(checker: Checker) throws {
        checker.section("URL shapes")
        let id = "dQw4w9WgXcQ"
        let shapes = [
            "https://www.youtube.com/watch?v=\(id)&t=30s",
            "https://youtu.be/\(id)",
            "https://www.youtube.com/shorts/\(id)",
            "https://www.youtube.com/live/\(id)",
            "https://m.youtube.com/watch?v=\(id)",
            "youtu.be/\(id)",
            "\"https://youtu.be/\(id)\"",
            id
        ]
        for shape in shapes {
            checker.expect(YouTubeURL.videoID(from: shape) == id, shape)
        }
        checker.expect(YouTubeURL.videoID(from: "https://vimeo.com/12345") == nil, "reject vimeo")
        checker.expect(
            YouTubeURL.videoID(from: "https://youtube.com.evil.test/watch?v=\(id)") == nil,
            "reject lookalike host"
        )

        checker.section("Classification (keyword fallback)")
        let tagger = HeuristicTagger()
        let cases: [(String, String)] = [
            ("Swift actors and structured concurrency", "Programming"),
            ("Sourdough bread for absolute beginners", "Cooking"),
            ("James Webb telescope first images explained", "Science"),
            ("Index funds vs ETFs", "Finance"),
            ("Tokyo in five days", "Travel"),
            ("Fall of the Roman empire", "History"),
            ("Colour grading a short film", "Film & Video")
        ]
        for (title, expected) in cases {
            let got = tagger.suggest(title: title).tags
            checker.expect(got.contains(expected), "\(title) → \(got.joined(separator: ", "))")
        }

        checker.section("Shelf behaviour")
        var library = Library()
        let first = Video(youtubeID: id, title: "A", channel: "C", tags: ["Music"])
        let second = Video(youtubeID: "jNQXAC9IVRw", title: "B", channel: "C", tags: ["Film & Video"])
        checker.expect(library.add(first), "add video")
        checker.expect(!library.add(first), "reject duplicate")
        checker.expect(library.add(second), "add second video")
        checker.expect(library.videos(filter: .tag("music")).count == 1, "tag filter is case-insensitive")
        checker.expect(library.videos(filter: .all, query: "jNQ").isEmpty, "search ignores the raw link")
        library.renameTag("Music", to: "Film & Video")
        checker.expect(library.tagCounts.count == 1, "rename merges categories")

        checker.section("Pin, merge and sort")
        var managed = Library()
        managed.add(Video(youtubeID: "aaaaaaaaaaa", title: "Bread", channel: "C", tags: ["Cooking", "Travel"]))
        managed.add(Video(youtubeID: "bbbbbbbbbbb", title: "Design", channel: "C", tags: ["Design"]))
        managed.pin("Travel")
        checker.expect(managed.pinnedTagCounts.map(\.name) == ["Travel"], "pin appears first")
        checker.expect(managed.unpinnedTagCounts(sortedBy: .mostVideos).map(\.name) == ["Cooking", "Design"],
                       "unpinned list sorted by count")
        let moved = managed.mergeTags("Travel", into: "Cooking")
        checker.expect(moved == 1, "merge reports the videos moved")
        checker.expect(managed.isPinned("Cooking") && !managed.isPinned("Travel"), "merge transfers the pin")
        checker.expect(managed.tagCounts.count == 2, "merge removes the source category")

        checker.section("Title search")
        var searchable = Library()
        searchable.add(Video(youtubeID: "ccccccccccc", title: "Actors in Swift", channel: "Point-Free",
                             tags: ["Programming"]))
        searchable.add(Video(youtubeID: "ddddddddddd", title: "Sourdough", channel: "Bake Club",
                             tags: ["Cooking"], note: "swift crumb"))
        checker.expect(searchable.videos(filter: .all, query: "swift", scope: .titles).count == 1,
                       "titles-only search ignores notes and categories")
        checker.expect(searchable.videos(filter: .all, query: "swift", scope: .everything).count == 2,
                       "everything search still finds notes")

        checker.section("Backup format")
        let data = try ShelfBackup.encode(library)
        checker.expect(try ShelfBackup.decode(data) == library, "backup round-trips")
        let rejected = (try? ShelfBackup.decode(Data("{\"nope\":true}".utf8))) == nil
        checker.expect(rejected, "foreign JSON is rejected")
        let raw = try JSONEncoder.iso8601.encode(library)
        checker.expect(try ShelfBackup.decode(raw) == library, "raw library.json is accepted")

        checker.section("Persistence")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tubeshelf-check-\(UUID().uuidString)")
        let temporaryStore = LibraryStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try temporaryStore.save(library)
        checker.expect(try temporaryStore.load() == library, "round-trip through disk")

        checker.section("Deck navigation")
        var deck = DeckModel(slides: library.videos(filter: .all))
        checker.expect(deck.position == 1, "starts on slide 1")
        checker.expect(deck.total == 2, "two slides")
        checker.expect(deck.showNext(), "advance")
        checker.expect(!deck.showNext(), "stops at the last slide")
        checker.expect(deck.showPrevious(), "go back")
    }

    // MARK: - Live model

    @MainActor
    static func probeModel() async {
        print("\nOn-device model")
        print("  status  \(TagEngine.status.shortLabel)")
        print("  detail  \(TagEngine.status.detail)")

        let samples = [
            ("SwiftUI concurrency: actors in practice", "Apple Developer"),
            ("Sourdough bread for absolute beginners", "Brian Lagerstrom"),
            ("The James Webb telescope, explained", "PBS Space Time")
        ]
        let engine = TagEngine()
        for (title, channel) in samples {
            let started = Date()
            let suggestion = await engine.suggest(title: title, channel: channel)
            let elapsed = String(format: "%.2fs", Date().timeIntervalSince(started))
            print("  • \(title)")
            print("    → \(suggestion.tags.joined(separator: ", "))  [\(suggestion.source.label), \(elapsed)]")
        }
    }

    // MARK: - Network

    static func fetchOne(_ raw: String) async -> Bool {
        guard let id = YouTubeURL.videoID(from: raw) else {
            print("Not a YouTube link: \(raw)")
            return false
        }
        do {
            let metadata = try await YouTubeMetadataService().fetch(videoID: id)
            print("Title   \(metadata.title)")
            print("Channel \(metadata.channel)")
            print("Length  \(metadata.durationSeconds.map { "\($0)s" } ?? "unknown")")
            print("Desc    \(metadata.description.prefix(160))")
            let environment = ProcessInfo.processInfo.environment
            let localAI = environment["TUBESHELF_AI_URL"].map {
                LocalAIConfig(
                    baseURL: $0,
                    model: environment["TUBESHELF_AI_MODEL"] ?? "system"
                )
            }
            let suggestion = await TagEngine().suggest(
                title: metadata.title,
                channel: metadata.channel,
                description: metadata.description,
                knownCategories: knownCategories(),
                localAI: localAI
            )
            print("Tags    \(suggestion.tags.joined(separator: ", "))  [\(suggestion.source.label)]")
            if !suggestion.note.isEmpty {
                print("Note    \(suggestion.note)")
            }
            return true
        } catch {
            print("Fetch failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Categories from every profile on this Mac, so suggestions behave like the
    /// app rather than a cold start.
    static func knownCategories() -> [String] {
        let store = ProfileStore()
        guard let profiles = try? store.profiles() else { return [] }
        var names = Set<String>()
        for profile in profiles {
            if let library = try? store.libraryStore(for: profile).load() {
                library.tagCounts.forEach { names.insert($0.name) }
            }
        }
        return names.sorted()
    }

    static func fetchPlaylist(_ raw: String) async -> Bool {
        guard let id = YouTubeURL.playlistID(from: raw) else {
            print("Not a playlist link: \(raw)")
            return false
        }
        do {
            let metadata = try await PlaylistService().fetch(playlistID: id)
            print("Playlist  \(metadata.title)")
            print("Items     \(metadata.items.count)\(metadata.truncated ? " (limit reached)" : "")")
            for item in metadata.items.prefix(6) {
                print("  • \(item.title) — \(item.channel)")
            }
            return true
        } catch {
            print("Playlist fetch failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Library maintenance

    static func seedDemo(store: LibraryStore) throws {
        var library = try store.load()
        var added = 0
        for sample in SampleShelf.all where library.add(sample) {
            added += 1
        }
        try store.save(library)
        print("Added \(added) examples. Library now has \(library.count) videos.")
        print(store.fileURL.path)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

final class Checker {
    private(set) var checks = 0
    private(set) var failures: [String] = []

    func expect(_ condition: Bool, _ label: String) {
        checks += 1
        if condition {
            print("  ok    \(label)")
        } else {
            print("  FAIL  \(label)")
            failures.append(label)
        }
    }

    func section(_ title: String) {
        print("\n\(title)")
    }

    func report() {
        print("\n\(checks - failures.count)/\(checks) checks passed")
    }
}
