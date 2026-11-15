import SwiftUI
import Observation
import TubeShelfCore

@MainActor
@Observable
final class AppModel {
    var library: Library
    var filter: ShelfFilter = .all
    var query: String = "" {
        didSet { if query != oldValue { pageIndex = 0 } }
    }
    var searchScope: SearchScope = .everything {
        didSet {
            Preferences.searchScope = searchScope
            if searchScope != oldValue { pageIndex = 0 }
        }
    }
    var sidebarQuery: String = ""
    var deck: DeckModel?
    var isAddPresented = false
    var isCategoryManagerPresented = false
    var isChannelBrowserPresented = false
    var isPlaylistImportPresented = false
    var isPlaylistCatalogPresented = false
    var isAddPlaylistToCatalogPresented = false
    var pendingPlaylistID: String?
    var deckTitle: String?
    /// Used by the debug snapshot mode to open the sheet with a playlist ready.
    var playlistImportPrefill: String?
    var pageIndex = 0
    /// When set, the grid and the deck use this shuffle instead of newest-first.
    var shuffleSeed: UInt64?
    var pageSize: Int = Preferences.pageSize {
        didSet {
            Preferences.pageSize = pageSize
            pageIndex = 0
        }
    }
    var editingVideoID: UUID?
    var toast: String?
    var searchFocusRequest = 0

    var categorySort: CategorySort = .mostVideos {
        didSet { Preferences.categorySort = categorySort }
    }
    var categorySortAscending: Bool = false {
        didSet { Preferences.categorySortAscending = categorySortAscending }
    }

    var store: LibraryStore
    var playlistStore: PlaylistStore
    var playlists: [PlaylistRecord] = []
    let profileStore: ProfileStore
    var profiles: [Profile]
    var activeProfileID: UUID
    var isProfileManagerPresented = false
    let modelStatus: OnDeviceModelStatus
    private let engine = TagEngine()
    private var toastTask: Task<Void, Never>?
    private var deckFilter: ShelfFilter = .all
    private var deckQuery: String = ""

    /// Release builds always use the real Application Support folder; the debug
    /// snapshot mode can point at a throwaway root for scale testing.
    static func defaultProfileStore() -> ProfileStore {
        #if DEBUG
        if let directory = SnapshotConfig.libraryDirectory {
            return ProfileStore(root: directory)
        }
        #endif
        return ProfileStore()
    }

    init(profileStore: ProfileStore) {
        self.profileStore = profileStore
        self.modelStatus = TagEngine.status
        self.categorySort = Preferences.categorySort
        self.categorySortAscending = Preferences.categorySortAscending
        self.searchScope = Preferences.searchScope

        let loaded = (try? profileStore.profiles()) ?? []
        let savedID = Preferences.activeProfileID.flatMap(UUID.init(uuidString:))
        let active = loaded.first(where: { $0.id == savedID }) ?? loaded.first

        self.profiles = loaded
        self.activeProfileID = active?.id ?? UUID()
        let activeDirectory = active.map { profileStore.directory(for: $0) } ?? profileStore.root
        self.store = active.map { profileStore.libraryStore(for: $0) }
            ?? LibraryStore(directory: profileStore.root)
        self.playlistStore = PlaylistStore(directory: activeDirectory)
        self.library = Library()

        if let active {
            Preferences.activeProfileID = active.id.uuidString
            do {
                self.library = try self.store.load()
            } catch {
                self.toast = "Could not read \(active.name): \(error.localizedDescription)"
            }
            self.playlists = (try? self.playlistStore.load()) ?? []
        } else {
            self.toast = "Could not open your profiles: using an empty shelf"
        }
    }

    var currentProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// Google Drive for Desktop mounts accounts under CloudStorage. The debug
    /// snapshot mode can point at a fake root so this path can be exercised.
    var cloudLocator: CloudDriveLocator {
        #if DEBUG
        if let root = SnapshotConfig.cloudRoot {
            return CloudDriveLocator(root: root)
        }
        #endif
        return CloudDriveLocator()
    }

    enum DriveStatus: Equatable {
        case ready(account: String)
        case notFound
    }

    var driveStatus: DriveStatus {
        let drives = cloudLocator.googleDrives()
        if let remembered = Preferences.driveAccountPath,
           let match = drives.first(where: { $0.myDrive.path == remembered }) {
            return .ready(account: match.accountName)
        }
        if let first = drives.first {
            return .ready(account: first.accountName)
        }
        return .notFound
    }

    // MARK: - Profiles

    func switchProfile(_ id: UUID) {
        guard id != activeProfileID,
              let profile = profiles.first(where: { $0.id == id })
        else { return }

        save()
        store = profileStore.libraryStore(for: profile)
        playlistStore = PlaylistStore(directory: profileStore.directory(for: profile))
        playlists = (try? playlistStore.load()) ?? []
        activeProfileID = id
        Preferences.activeProfileID = id.uuidString

        do {
            library = try store.load()
        } catch {
            library = Library()
            toast = "Could not read \(profile.name): \(error.localizedDescription)"
        }

        filter = .all
        query = ""
        sidebarQuery = ""
        pageIndex = 0
        deck = nil
        editingVideoID = nil
        isAddPresented = false
        flash("Switched to \(profile.name)")
    }

    /// Creates a shelf from a file without touching any other profile.
    @discardableResult
    func addProfile(name: String, library incoming: Library, importedFrom: String?) throws -> Profile {
        let unique = profileStore.uniqueName(name, among: profiles)
        let profile = try profileStore.create(
            name: unique,
            library: incoming,
            importedFrom: importedFrom
        )
        profiles = (try? profileStore.profiles()) ?? (profiles + [profile])
        switchProfile(profile.id)
        return profile
    }

    func videoCount(for profile: Profile) -> Int {
        (try? profileStore.libraryStore(for: profile).load().count) ?? 0
    }

    /// Other shelves that actually contain something — used to offer a way back
    /// when the current profile is empty.
    var otherPopulatedProfiles: [(profile: Profile, count: Int)] {
        profiles
            .filter { $0.id != activeProfileID }
            .map { ($0, videoCount(for: $0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
    }

    func createEmptyProfile(named name: String) {
        do {
            try addProfile(name: name, library: Library(), importedFrom: nil)
        } catch {
            flash("Could not create profile: \(error.localizedDescription)")
        }
    }

    func renameProfile(_ id: UUID, to newName: String) {
        let cleaned = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty,
              var profile = profiles.first(where: { $0.id == id })
        else { return }
        profile.name = cleaned
        do {
            try profileStore.saveMetadata(profile)
            profiles = try profileStore.profiles()
            flash("Renamed to \(cleaned)")
        } catch {
            flash("Could not rename: \(error.localizedDescription)")
        }
    }

    /// Deletes a profile by moving its folder to the Trash. The last profile is
    /// never removable, and the active one hands over to a neighbour first.
    func deleteProfile(_ id: UUID) {
        guard profiles.count > 1,
              let profile = profiles.first(where: { $0.id == id })
        else { return }

        if id == activeProfileID,
           let next = profiles.first(where: { $0.id != id }) {
            switchProfile(next.id)
        }

        do {
            try profileStore.trash(profile)
            profiles = (try? profileStore.profiles()) ?? profiles.filter { $0.id != id }
            flash("Moved \(profile.name) to the Trash")
        } catch {
            flash("Could not delete \(profile.name): \(error.localizedDescription)")
        }
    }

    // MARK: - Derived

    var visibleVideos: [Video] {
        let ordered = library.videos(filter: filter, query: query, scope: searchScope)
        guard let shuffleSeed else { return ordered }
        return SeededShuffle.shuffle(ordered, seed: shuffleSeed)
    }

    var isShuffled: Bool { shuffleSeed != nil }

    /// A new random order every click; keeping the mode on between clicks.
    func shuffle() {
        shuffleSeed = UInt64.random(in: 1...UInt64.max)
        pageIndex = 0
    }

    func clearShuffle() {
        shuffleSeed = nil
        pageIndex = 0
    }

    /// Pagination for the grid. The deck deliberately still receives every
    /// matching video, so presenting a category is never cut short by a page.
    var pageWindow: PageWindow {
        PageWindow(total: visibleVideos.count, pageSize: pageSize, pageIndex: pageIndex)
    }

    var pagedVideos: [Video] {
        let all = visibleVideos
        return Array(PageWindow(total: all.count, pageSize: pageSize, pageIndex: pageIndex).slice(all))
    }

    var showsPager: Bool { pageWindow.hasMultiplePages }

    func goToPage(_ index: Int) {
        pageIndex = pageWindow.page(index).pageIndex
    }

    func nextPage() {
        goToPage(pageWindow.pageIndex + 1)
    }

    func previousPage() {
        goToPage(pageWindow.pageIndex - 1)
    }

    var pinnedTagCounts: [TagCount] {
        matchingSidebarQuery(library.pinnedTagCounts)
    }

    var unpinnedTagCounts: [TagCount] {
        matchingSidebarQuery(
            library.unpinnedTagCounts(sortedBy: categorySort, ascending: categorySortAscending)
        )
    }

    var hasPinnedCategories: Bool { !pinnedTagCounts.isEmpty }

    /// What the sidebar shows: the biggest channels, plus whichever channel is
    /// currently selected even if it is not in the top few.
    var sidebarChannels: [TagCount] {
        let all = library.channelCounts(sortedBy: .mostVideos)
        let trimmed = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            let needle = SearchText.normalize(trimmed)
            return Array(all.filter { SearchText.matches(needle: needle, haystack: $0.name) }.prefix(6))
        }

        var picks = Array(all.prefix(5))
        if let active = filter.channelName,
           !picks.contains(where: { $0.name.caseInsensitiveCompare(active) == .orderedSame }),
           let match = all.first(where: { $0.name.caseInsensitiveCompare(active) == .orderedSame }) {
            picks.insert(match, at: 0)
        }
        return picks
    }

    var channelTotal: Int {
        library.channelCounts().count
    }

    var channelCounts: [TagCount] {
        let trimmed = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = library.channelCounts(sortedBy: categorySort, ascending: categorySortAscending)
        guard !trimmed.isEmpty else { return all }
        let needle = SearchText.normalize(trimmed)
        return all.filter { SearchText.matches(needle: needle, haystack: $0.name) }
    }

    private func matchingSidebarQuery(_ counts: [TagCount]) -> [TagCount] {
        let trimmed = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return counts }
        let needle = SearchText.normalize(trimmed)
        return counts.filter { SearchText.matches(needle: needle, haystack: $0.name) }
    }

    var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var subtitle: String {
        let shown = visibleVideos.count
        if isSearching {
            return "\(shown) result\(shown == 1 ? "" : "s") in \(searchScope.label.lowercased())"
        }
        switch filter {
        case .all: return "\(library.count) saved video\(library.count == 1 ? "" : "s")"
        case .favorites: return "\(shown) favorite\(shown == 1 ? "" : "s")"
        case .unwatched: return "\(shown) still to watch"
        case .unsorted: return "\(shown) without a category"
        case .tag: return "\(shown) video\(shown == 1 ? "" : "s") in this category"
        case .channel(let name): return "\(shown) video\(shown == 1 ? "" : "s") from \(name)"
        }
    }

    var editingVideo: Video? {
        guard let id = editingVideoID else { return nil }
        return library.video(id: id)
    }

    // MARK: - Navigation

    func select(_ newFilter: ShelfFilter) {
        filter = newFilter
        query = ""
        pageIndex = 0
    }

    func openDeck(startAt video: Video) {
        let slides = visibleVideos
        guard !slides.isEmpty else { return }
        deckFilter = filter
        deckQuery = query
        deckTitle = filter.title
        deck = DeckModel(slides: slides, startAt: video.id)
    }

    func openDeckForTag(_ tag: String) {
        filter = .tag(tag)
        query = ""
        guard let first = visibleVideos.first else { return }
        openDeck(startAt: first)
    }

    func closeDeck() {
        deck = nil
        deckTitle = nil
    }

    // MARK: - Playlist catalog

    func playlist(id: String) -> PlaylistRecord? {
        playlists.first { $0.id == id }
    }

    func openPlaylistCatalog(id: String? = nil) {
        pendingPlaylistID = id
        isPlaylistCatalogPresented = true
    }

    /// Saves a fetched playlist as a course. Re-adding updates the chapter list
    /// while keeping ticks for chapters that still exist.
    @discardableResult
    func catalogPlaylist(_ metadata: PlaylistMetadata) -> PlaylistRecord {
        if var existing = playlist(id: metadata.playlistID) {
            existing.title = metadata.title
            existing.channel = metadata.channel
            existing.replaceItems(metadata.items)
            existing.isTruncated = metadata.truncated
            if let index = playlists.firstIndex(where: { $0.id == existing.id }) {
                playlists[index] = existing
            }
            savePlaylists()
            flash("Updated \(existing.title)")
            return existing
        }

        let record = PlaylistRecord(
            id: metadata.playlistID,
            title: metadata.title,
            channel: metadata.channel,
            items: metadata.items,
            isTruncated: metadata.truncated
        )
        playlists.insert(record, at: 0)
        savePlaylists()
        flash("Saved \(record.title) to the catalog")
        return record
    }

    func removePlaylist(id: String) {
        playlists.removeAll { $0.id == id }
        savePlaylists()
        flash("Removed from the catalog")
    }

    /// Per-playlist progress; ticking a chapter that is on the shelf also marks
    /// that video watched there.
    func toggleChapter(playlistID: String, videoID: String) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let watched = !playlists[index].isWatched(videoID)
        playlists[index].setWatched(watched, videoID: videoID)
        if let video = library.video(youtubeID: videoID) {
            library.setWatchStatus(watched ? .done : .unwatched, for: video.id)
        }
        savePlaylists()
        save()
        refreshDeck()
        if let record = playlist(id: playlistID) {
            flash("\(record.watchedCount) of \(record.chapterCount) watched")
        }
    }

    /// Presents the chapters that are already on the shelf, in playlist order.
    func presentPlaylist(_ record: PlaylistRecord) {
        let slides = record.items.compactMap { library.video(youtubeID: $0.videoID) }
        guard let first = slides.first else {
            flash("Add a chapter to the shelf first")
            return
        }
        deckTitle = record.title
        deck = DeckModel(slides: slides, startAt: first.id)
        isPlaylistCatalogPresented = false
    }

    /// Adds one chapter to the shelf, with the categories reviewed in the editor.
    @discardableResult
    func addChapterToShelf(_ item: PlaylistItem, tags: [String]) -> Bool {
        guard !library.contains(youtubeID: item.videoID) else {
            flash("That chapter is already on your shelf")
            return false
        }
        let video = Video(
            youtubeID: item.videoID,
            title: item.title,
            channel: item.channel,
            tags: TagNormalizer.merge(tags),
            durationSeconds: item.durationSeconds
        )
        guard library.add(video) else { return false }
        save()
        flash("Added “\(item.title)” to your shelf")
        return true
    }

    func suggestedTags(for item: PlaylistItem) -> [String] {
        HeuristicTagger().suggest(
            title: item.title,
            channel: item.channel,
            limit: 3,
            knownCategories: library.tagCounts.map(\.name)
        ).tags
    }

    func addMissingVideos(from record: PlaylistRecord) {
        guard let url = record.shareURL?.absoluteString else { return }
        playlistImportPrefill = url
        isPlaylistCatalogPresented = false
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.isPlaylistImportPresented = true
        }
    }

    func savePlaylists() {
        do {
            try playlistStore.save(playlists)
        } catch {
            flash("Could not save the playlist catalog: \(error.localizedDescription)")
        }
    }

    func revealVideo(_ video: Video) {
        deck = nil
        editingVideoID = nil
        if filter.tagName != nil, !(video.tags.contains { $0.caseInsensitiveCompare(filter.tagName ?? "") == .orderedSame }) {
            filter = .all
        }
        query = video.title
    }

    // MARK: - Mutations

    @discardableResult
    func add(_ video: Video) -> Bool {
        guard library.add(video) else {
            flash("That video is already on your shelf")
            return false
        }
        save()
        flash("Saved\(video.tags.isEmpty ? "" : " to \(video.tags[0])")")
        Task { await ThumbnailCache.shared.prefetch(videoID: video.youtubeID) }
        return true
    }

    func updateVideo(_ video: Video) {
        library.update(video)
        save()
        refreshDeck()
        flash("Updated “\(video.title)”")
    }

    func delete(_ video: Video) {
        library.remove(id: video.id)
        if editingVideoID == video.id { editingVideoID = nil }
        save()
        refreshDeck()
        flash("Removed from shelf")
    }

    func toggleWatched(_ video: Video) {
        let next: WatchStatus = video.watchStatus == .done ? .unwatched : .done
        library.setWatchStatus(next, for: video.id)
        save()
        refreshDeck()
        flash(next == .done ? "Marked as watched" : "Marked as unwatched")
    }

    func setWatchStatus(_ status: WatchStatus, for video: Video) {
        library.setWatchStatus(status, for: video.id)
        save()
        refreshDeck()
    }

    func toggleFavorite(_ video: Video) {
        library.toggleFavorite(id: video.id)
        save()
        refreshDeck()
    }

    func setTags(_ tags: [String], for videoID: UUID) {
        library.setTags(tags, for: videoID)
        save()
        refreshDeck()
    }

    func setNote(_ note: String, for videoID: UUID) {
        library.setNote(note, for: videoID)
        save()
    }

    func renameTag(_ old: String, to new: String) {
        library.renameTag(old, to: new)
        if case .tag(let name) = filter, name.caseInsensitiveCompare(old) == .orderedSame,
           let cleaned = TagNormalizer.canonical(new) {
            filter = .tag(cleaned)
        }
        save()
        refreshDeck()
    }

    func deleteTag(_ name: String) {
        library.deleteTag(name)
        if case .tag(let current) = filter, current.caseInsensitiveCompare(name) == .orderedSame {
            filter = .all
        }
        save()
        refreshDeck()
    }

    func togglePin(_ name: String) {
        let isPinned = library.togglePin(name)
        save()
        flash(isPinned ? "Pinned \(name)" : "Unpinned \(name)")
    }

    @discardableResult
    func mergeCategories(_ source: String, into destination: String) -> Int {
        let moved = library.mergeTags(source, into: destination)
        if case .tag(let current) = filter, current.caseInsensitiveCompare(source) == .orderedSame {
            filter = .tag(TagNormalizer.canonical(destination) ?? destination)
        }
        save()
        refreshDeck()
        if moved > 0 {
            flash("Merged \(source) into \(TagNormalizer.canonical(destination) ?? destination) · \(moved) video\(moved == 1 ? "" : "s")")
        }
        return moved
    }

    func focusSearch() {
        searchFocusRequest += 1
    }

    func openCategoryManager() {
        isCategoryManagerPresented = true
    }

    func openChannelBrowser() {
        isChannelBrowserPresented = true
    }

    func openPlaylistImport() {
        isPlaylistImportPresented = true
    }

    /// Adds the chosen playlist items with the categories that were reviewed in
    /// the sheet. Nothing is guessed during the import: what you saw is what gets
    /// filed. The library is saved once, not once per video.
    @discardableResult
    func importPlaylist(
        _ metadata: PlaylistMetadata,
        selection: Set<String>,
        tagsByVideo: [String: [String]]
    ) -> Int {
        var added = 0
        for item in metadata.items where selection.contains(item.videoID) {
            guard !library.contains(youtubeID: item.videoID) else { continue }
            let video = Video(
                youtubeID: item.videoID,
                title: item.title,
                channel: item.channel,
                tags: TagNormalizer.merge(tagsByVideo[item.videoID] ?? []),
                durationSeconds: item.durationSeconds
            )
            if library.add(video) { added += 1 }
        }
        save()
        flash("Added \(added) video\(added == 1 ? "" : "s") from “\(metadata.title)”")
        return added
    }

    /// Categories offered in the playlist sheet: the shelf's own first, then the
    /// built-in library.
    var categoryChoices: [String] {
        var names = library.tagCounts.map(\.name)
        for name in TagTaxonomy.names where !names.contains(where: {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }) {
            names.append(name)
        }
        return names
    }

    func showChannel(_ name: String) {
        select(.channel(name))
    }

    func openDeckForChannel(_ name: String) {
        filter = .channel(name)
        query = ""
        pageIndex = 0
        guard let first = visibleVideos.first else { return }
        openDeck(startAt: first)
    }

    // MARK: - Suggestions

    func suggestTags(for metadata: VideoMetadata) async -> TagSuggestion {
        await engine.suggest(
            title: metadata.title,
            channel: metadata.channel,
            description: metadata.description,
            channelHint: library.channelAffinity(for: metadata.channel),
            knownCategories: library.tagCounts.map(\.name)
        )
    }

    // MARK: - Backup

    @discardableResult
    func backup(to url: URL) throws -> Int {
        try BackupService().write(library, playlists: playlists, to: url)
        flash("Backed up \(library.count) video\(library.count == 1 ? "" : "s")")
        return library.count
    }

    @discardableResult
    func restore(from url: URL) throws -> Int {
        let contents = try BackupService().readContents(from: url)
        let incoming = contents.library

        // Keep the outgoing library beside the store so choosing the wrong file
        // is always recoverable.
        if let data = try? Data(contentsOf: store.fileURL) {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = store.directory.appendingPathComponent("library-before-restore-\(stamp).json")
            try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try? data.write(to: aside, options: .atomic)
        }

        library = incoming
        playlists = contents.playlists
        savePlaylists()
        filter = .all
        query = ""
        sidebarQuery = ""
        pageIndex = 0
        deck = nil
        save()
        flash("Restored \(incoming.count) video\(incoming.count == 1 ? "" : "s")")
        return incoming.count
    }

    // MARK: - Persistence

    func save() {
        // A category can disappear when its last video is deleted or retagged;
        // drop the orphaned pin before it reaches disk.
        library.prunePinnedTags()
        // If deletions emptied the last page, fall back to a page that exists.
        pageIndex = PageWindow(
            total: visibleVideos.count,
            pageSize: pageSize,
            pageIndex: pageIndex
        ).pageIndex
        do {
            try store.save(library)
        } catch {
            flash("Saving failed: \(error.localizedDescription)")
        }
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func refreshDeck() {
        guard var current = deck else { return }
        current.refresh(with: library.videos(filter: deckFilter, query: deckQuery))
        if current.total == 0 {
            deck = nil
        } else {
            deck = current
        }
    }

    // MARK: - Samples

    /// Six real videos, added only when the person asks for them.
    func addSamples() {
        var added = 0
        for sample in SampleShelf.all {
            if library.add(sample) { added += 1 }
        }
        save()
        flash(added > 0 ? "Added \(added) example videos" : "Examples are already on the shelf")
        for sample in SampleShelf.all {
            Task { await ThumbnailCache.shared.prefetch(videoID: sample.youtubeID) }
        }
    }
}

/// Small user preferences that should survive a relaunch but do not belong in
/// the library file (which is data the person can back up or edit).
@MainActor
enum Preferences {
    private static let defaults = UserDefaults.standard

    static var categorySort: CategorySort {
        get { CategorySort(rawValue: defaults.string(forKey: "categorySort") ?? "") ?? .mostVideos }
        set { defaults.set(newValue.rawValue, forKey: "categorySort") }
    }

    static var categorySortAscending: Bool {
        get { defaults.bool(forKey: "categorySortAscending") }
        set { defaults.set(newValue, forKey: "categorySortAscending") }
    }

    static var searchScope: SearchScope {
        get { SearchScope(rawValue: defaults.string(forKey: "searchScope") ?? "") ?? .everything }
        set { defaults.set(newValue.rawValue, forKey: "searchScope") }
    }

    static let pageSizeOptions = [24, 48, 96, 144]

    static var driveAccountPath: String? {
        get { defaults.string(forKey: "driveAccountPath") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "driveAccountPath")
            } else {
                defaults.removeObject(forKey: "driveAccountPath")
            }
        }
    }

    static var activeProfileID: String? {
        get { defaults.string(forKey: "activeProfileID") }
        set {
            if let newValue {
                defaults.set(newValue, forKey: "activeProfileID")
            } else {
                defaults.removeObject(forKey: "activeProfileID")
            }
        }
    }

    static var pageSize: Int {
        get {
            let stored = defaults.integer(forKey: "pageSize")
            return pageSizeOptions.contains(stored) ? stored : 48
        }
        set { defaults.set(newValue, forKey: "pageSize") }
    }
}
