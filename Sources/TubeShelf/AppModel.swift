import SwiftUI
import Observation
import TubeShelfCore

/// State of the opt-in local model server, shown in Settings.
enum LocalAIState: Equatable {
    case idle
    case checking
    case reachable([String])
    case unreachable(String)
}

/// How the content pane presents the current filter.
enum ShelfPresentation: String, CaseIterable, Identifiable {
    case grid
    case map
    case orbit

    var id: String { rawValue }
}

/// One cell in the shelf grid: a video, or a course in a category view.
extension ShelfItem {
    var deckSlide: DeckSlide {
        switch self {
        case .video(let video): .video(video)
        case .playlist(let playlist): .playlist(playlist)
        }
    }
}

enum ShelfItem: Identifiable {
    case video(Video)
    case playlist(PlaylistRecord)

    var id: String {
        switch self {
        case .video(let video): "v-\(video.id)"
        case .playlist(let playlist): "p-\(playlist.id)"
        }
    }

    var addedAt: Date {
        switch self {
        case .video(let video): video.addedAt
        case .playlist(let playlist): playlist.addedAt
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var library: Library
    /// The last state shared with the web: a successful backup or restore.
    var mergeBase: ShelfSnapshot?
    /// Set when a restore has conflicts and the review sheet should open.
    var mergeReview: MergeReviewState?
    var filter: ShelfFilter = .all
    var query: String = "" {
        didSet {
            if query != oldValue {
                pageIndex = 0
                resetSelection()
            }
        }
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
    var isTidyPresented = false
    var isBulkAddPresented = false
    var isBulkRemovePresented = false

    var spotlightEnabled: Bool = Preferences.spotlightEnabled {
        didSet {
            Preferences.spotlightEnabled = spotlightEnabled
            scheduleSpotlight()
        }
    }

    var localAIEnabled: Bool = Preferences.localAIEnabled {
        didSet {
            Preferences.localAIEnabled = localAIEnabled
            if localAIEnabled {
                Task { await checkLocalAI() }
            } else {
                localAIState = .idle
            }
        }
    }
    var localAIURL: String = Preferences.localAIURL {
        didSet { Preferences.localAIURL = localAIURL }
    }
    var localAIModel: String = Preferences.localAIModel {
        didSet { Preferences.localAIModel = localAIModel }
    }
    var localAIState: LocalAIState = .idle
    /// nil unless a server is enabled and its URL is usable.
    var localAIConfig: LocalAIConfig? {
        guard localAIEnabled else { return nil }
        let url = localAIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return nil }
        let model = localAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return LocalAIConfig(baseURL: url, model: model.isEmpty ? "system" : model)
    }

    /// A visible answer to "is the server still running after a restart?".
    func checkLocalAI() async {
        guard let config = localAIConfig else {
            localAIState = .idle
            return
        }
        localAIState = .checking
        do {
            let models = try await LocalAIClient(config: config).models()
            localAIState = .reachable(models)
        } catch {
            localAIState = .unreachable(error.localizedDescription)
        }
    }
    var isAddPlaylistToCatalogPresented = false
    /// Debug snapshot hook: opens the catalog sheet with a playlist ready.
    var catalogPlaylistPrefill: String?
    var pendingPlaylistID: String?
    var deckTitle: String?
    /// Used by the debug snapshot mode to open the sheet with a playlist ready.
    var playlistImportPrefill: String?
    var pageIndex = 0
    /// When set, the grid and the deck use this shuffle instead of newest-first.
    var shuffleSeed: UInt64?
    /// The catalog has its own shuffle so browsing videos and browsing courses do
    /// not disturb each other.
    var playlistShuffleSeed: UInt64?
    var pageSize: Int = Preferences.pageSize {
        didSet {
            Preferences.pageSize = pageSize
            pageIndex = 0
        }
    }
    var editingVideoID: UUID?
    var toast: String?
    var toastActionTitle: String?
    var toastAction: (() -> Void)?

    // Bulk selection
    var isSelecting = false
    var selectedVideoIDs: Set<UUID> = []
    var selectionAnchorID: UUID?
    private var pendingUndo: BulkEdit?

    /// Grid or map. Interface state, never library data.
    var presentation: ShelfPresentation = Preferences.presentation {
        didSet {
            Preferences.presentation = presentation
            if presentation != .grid, isSelecting {
                exitSelection()
            }
        }
    }

    struct BulkEdit {
        var tags: [UUID: [String]] = [:]
        var favorites: [UUID: Bool] = [:]
        var watched: [UUID: WatchStatus] = [:]
    }
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
            self.mergeBase = MergeBaseStore(directory: activeDirectory).load()
            scheduleSpotlight()
            self.library.retainPins(among: Set(
                (self.library.tagCounts.map(\.name) + self.playlists.flatMap(\.tags)).map { $0.lowercased() }
            ))
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
        mergeBase = MergeBaseStore(directory: profileStore.directory(for: profile)).load()

        filter = .all
        query = ""
        sidebarQuery = ""
        pageIndex = 0
        deck = nil
        editingVideoID = nil
        isAddPresented = false
        resetSelection()
        scheduleSpotlight()
        flash("Switched to \(profile.name)")
    }

    /// Creates a shelf from a file without touching any other profile.
    @discardableResult
    func addProfile(
        name: String,
        library incoming: Library,
        playlists incomingPlaylists: [PlaylistRecord] = [],
        importedFrom: String?
    ) throws -> Profile {
        let unique = profileStore.uniqueName(name, among: profiles)
        let profile = try profileStore.create(
            name: unique,
            library: incoming,
            importedFrom: importedFrom
        )
        if !incomingPlaylists.isEmpty {
            try PlaylistStore(directory: profileStore.directory(for: profile))
                .save(incomingPlaylists)
        }
        profiles = (try? profileStore.profiles()) ?? (profiles + [profile])
        switchProfile(profile.id)
        let base = ShelfSnapshot(library: incoming, playlists: incomingPlaylists)
        mergeBase = base
        try? MergeBaseStore(directory: profileStore.directory(for: profile)).save(base)
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

    /// A category view mixes courses with videos; every other view stays video-only.
    var visibleItems: [ShelfItem] {
        var items = visibleVideos.map(ShelfItem.video)
        guard let tag = filter.tagName else { return items }
        items.append(contentsOf: playlistsTagged(tag).map(ShelfItem.playlist))

        if let shuffleSeed {
            // Sorting after the videos were shuffled would undo the shuffle.
            return SeededShuffle.shuffle(items, seed: shuffleSeed)
        }
        return items.sorted { $0.addedAt > $1.addedAt }
    }

    func playlistsTagged(_ tag: String) -> [PlaylistRecord] {
        playlistsTagged(tag, query: query)
    }

    private func playlistsTagged(_ tag: String, query: String) -> [PlaylistRecord] {
        let needle = SearchText.normalize(query)
        return playlists.filter { record in
            guard record.hasTag(tag) else { return false }
            guard !needle.isEmpty else { return true }
            return SearchText.matches(needle: needle, haystack: "\(record.title) \(record.channel)")
        }
    }

    func playlistCount(for tag: String) -> Int {
        playlists.filter { $0.hasTag(tag) }.count
    }

    var isShuffled: Bool { shuffleSeed != nil }

    var isBrowsingPlaylists: Bool { filter == .playlists }

    /// The catalog grid honours the same search field as the shelf.
    var visiblePlaylists: [PlaylistRecord] {
        let needle = SearchText.normalize(query)
        let filtered = needle.isEmpty ? playlists : playlists.filter { record in
            SearchText.matches(needle: needle, haystack: "\(record.title) \(record.channel)")
        }
        guard let playlistShuffleSeed else { return filtered }
        return SeededShuffle.shuffle(filtered, seed: playlistShuffleSeed)
    }

    var isPlaylistShuffled: Bool { playlistShuffleSeed != nil }

    /// Shuffle whichever list is on screen.
    var isCurrentListShuffled: Bool {
        isBrowsingPlaylists ? isPlaylistShuffled : isShuffled
    }

    func shuffleCurrent() {
        if isBrowsingPlaylists {
            playlistShuffleSeed = UInt64.random(in: 1...UInt64.max)
        } else {
            shuffle()
        }
    }

    func clearCurrentShuffle() {
        if isBrowsingPlaylists {
            playlistShuffleSeed = nil
        } else {
            clearShuffle()
        }
    }

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
        PageWindow(total: visibleItems.count, pageSize: pageSize, pageIndex: pageIndex)
    }

    var pagedItems: [ShelfItem] {
        let all = visibleItems
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

    /// Categories as the sidebar sees them: videos and courses together.
    var combinedTagCounts: [TagCount] {
        var counts: [String: Int] = [:]
        var spelling: [String: String] = [:]
        func add(_ name: String, _ count: Int) {
            let key = name.lowercased()
            counts[key, default: 0] += count
            if spelling[key] == nil { spelling[key] = name }
        }
        for tag in library.tagCounts { add(tag.name, tag.count) }
        for record in playlists {
            for tag in record.tags { add(tag, 1) }
        }
        let merged = counts.map { TagCount(name: spelling[$0.key] ?? $0.key, count: $0.value) }
        return Self.sort(merged, by: categorySort, ascending: categorySortAscending)
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

    var pinnedTagCounts: [TagCount] {
        let counts = combinedTagCounts
        let pinned = library.pinnedTags.compactMap { pin in
            counts.first { $0.name.caseInsensitiveCompare(pin) == .orderedSame }
        }
        return matchingSidebarQuery(pinned)
    }

    var unpinnedTagCounts: [TagCount] {
        let pinnedKeys = Set(library.pinnedTags.map { $0.lowercased() })
        let rest = combinedTagCounts.filter { !pinnedKeys.contains($0.name.lowercased()) }
        return matchingSidebarQuery(rest)
    }

    /// Pinned channels keep pin order, then respect the sidebar filter.
    var pinnedChannelCounts: [TagCount] {
        matchingSidebarQuery(library.pinnedChannelCounts)
    }

    /// Pins are valid if any video *or course* still carries the category, and if
    /// a pinned channel still has at least one video.
    private func prunePins() {
        library.retainPins(among: Set(combinedTagCounts.map { $0.name.lowercased() }))
        library.retainChannelPins(among: Set(library.channelCounts().map { $0.name.lowercased() }))
    }

    var hasPinnedCategories: Bool { !pinnedTagCounts.isEmpty }
    var hasPinnedChannels: Bool { !pinnedChannelCounts.isEmpty }
    var hasPinnedItems: Bool { hasPinnedCategories || hasPinnedChannels }

    /// What the sidebar shows: the biggest unpinned channels, plus whichever
    /// channel is currently selected even if it is not in the top few. A pinned
    /// channel is drawn in the Pinned section instead, so it must not repeat here.
    var sidebarChannels: [TagCount] {
        let pinnedKeys = Set(library.pinnedChannels.map { $0.lowercased() })
        let all = library.channelCounts(sortedBy: .mostVideos)
            .filter { !pinnedKeys.contains($0.name.lowercased()) }
        let trimmed = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty {
            let needle = SearchText.normalize(trimmed)
            return Array(all.filter { SearchText.matches(needle: needle, haystack: $0.name) }.prefix(6))
        }

        var picks = Array(all.prefix(5))
        if let active = filter.channelName,
           !pinnedKeys.contains(active.lowercased()),
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

    var presentationHint: String {
        switch presentation {
        case .grid:
            return ""
        case .map:
            if let tag = filter.tagName {
                return "\(tag) · click another node to filter"
            }
            return "Click a category to filter · double-click to open the shelf"
        case .orbit:
            if let tag = filter.tagName {
                return "\(tag) · drag to orbit · click another sphere to filter"
            }
            return "Drag to orbit · right-drag to pan · scroll to zoom · click to filter"
        }
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
        case .tag:
            guard let tag = filter.tagName else { return "\(shown) videos" }
            let courses = playlistCount(for: tag)
            return "\(shown) video\(shown == 1 ? "" : "s")" + (courses > 0 ? " · \(courses) course\(courses == 1 ? "" : "s")" : "")
        case .channel(let name): return "\(shown) video\(shown == 1 ? "" : "s") from \(name)"
        case .playlists:
            let chapters = playlists.reduce(0) { $0 + $1.chapterCount }
            return "\(playlists.count) course\(playlists.count == 1 ? "" : "s") · \(chapters) chapters"
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
        resetSelection()
    }

    // MARK: - Selection

    var selectedVideos: [Video] {
        library.videos.filter { selectedVideoIDs.contains($0.id) }
    }

    var selectedCount: Int { selectedVideoIDs.count }

    var pagedVideoIDs: [UUID] {
        pagedItems.compactMap { item in
            if case .video(let video) = item { return video.id }
            return nil
        }
    }

    /// Categories present in the current selection, for the remove menu.
    var categoriesInSelection: [String] {
        TagNormalizer.merge(selectedVideos.flatMap(\.tags)).sorted()
    }

    func beginSelection(with video: Video) {
        isSelecting = true
        selectedVideoIDs.insert(video.id)
        selectionAnchorID = video.id
    }

    func toggleSelection(_ video: Video) {
        if selectedVideoIDs.contains(video.id) {
            selectedVideoIDs.remove(video.id)
        } else {
            selectedVideoIDs.insert(video.id)
        }
        selectionAnchorID = video.id
    }

    func selectRange(to video: Video) {
        let ids = pagedVideoIDs
        guard let anchor = selectionAnchorID,
              let start = ids.firstIndex(of: anchor),
              let end = ids.firstIndex(of: video.id)
        else {
            toggleSelection(video)
            return
        }
        let bounds = start <= end ? start...end : end...start
        selectedVideoIDs.formUnion(ids[bounds])
    }

    func selectPage() {
        selectedVideoIDs.formUnion(pagedVideoIDs)
        selectionAnchorID = pagedVideoIDs.first
    }

    func clearSelection() {
        selectedVideoIDs.removeAll()
        selectionAnchorID = nil
    }

    func resetSelection() {
        isSelecting = false
        clearSelection()
        pendingUndo = nil
    }

    func exitSelection() {
        resetSelection()
    }

    // MARK: - Bulk edits

    private func snapshot(for ids: Set<UUID>) -> BulkEdit {
        var snapshot = BulkEdit()
        for video in library.videos where ids.contains(video.id) {
            snapshot.tags[video.id] = video.tags
            snapshot.favorites[video.id] = video.isFavorite
            snapshot.watched[video.id] = video.watchStatus
        }
        return snapshot
    }

    func bulkAddTag(_ tag: String) {
        guard let cleaned = TagNormalizer.canonical(tag) else { return }
        let ids = selectedVideoIDs
        guard !ids.isEmpty else { return }
        pendingUndo = snapshot(for: ids)
        let changed = library.addTag(cleaned, to: ids)
        save()
        refreshDeck()
        flash(
            "Added \(cleaned) to \(changed) video\(changed == 1 ? "" : "s")",
            actionTitle: "Undo"
        ) { [weak self] in self?.undoBulkEdit() }
    }

    func bulkRemoveTag(_ tag: String) {
        let ids = selectedVideoIDs
        guard !ids.isEmpty else { return }
        pendingUndo = snapshot(for: ids)
        let changed = library.removeTag(tag, from: ids)
        save()
        refreshDeck()
        flash(
            "Removed \(tag) from \(changed) video\(changed == 1 ? "" : "s")",
            actionTitle: "Undo"
        ) { [weak self] in self?.undoBulkEdit() }
    }

    func bulkSetFavorite(_ value: Bool) {
        let ids = selectedVideoIDs
        guard !ids.isEmpty else { return }
        pendingUndo = snapshot(for: ids)
        library.setFavorite(value, for: ids)
        save()
        refreshDeck()
        flash(value ? "Favorited \(ids.count)" : "Unfavorited \(ids.count)", actionTitle: "Undo") { [weak self] in
            self?.undoBulkEdit()
        }
    }

    func bulkToggleWatched() {
        let ids = selectedVideoIDs
        guard !ids.isEmpty else { return }
        let allWatched = selectedVideos.allSatisfy { $0.watchStatus == .done }
        pendingUndo = snapshot(for: ids)
        library.setWatchStatus(allWatched ? .unwatched : .done, for: ids)
        save()
        refreshDeck()
        flash(allWatched ? "Marked \(ids.count) unwatched" : "Marked \(ids.count) watched", actionTitle: "Undo") { [weak self] in
            self?.undoBulkEdit()
        }
    }

    func bulkRemoveSelected() {
        let ids = selectedVideoIDs
        guard !ids.isEmpty else { return }
        pendingUndo = nil
        for id in ids { library.remove(id: id) }
        save()
        refreshDeck()
        let removed = ids.count
        clearSelection()
        isSelecting = false
        flash("Removed \(removed) video\(removed == 1 ? "" : "s") from the shelf")
    }

    private func undoBulkEdit() {
        guard let snapshot = pendingUndo else { return }
        for (id, tags) in snapshot.tags { library.setTags(tags, for: id) }
        for (id, favorite) in snapshot.favorites { library.setFavorite(favorite, for: [id]) }
        for (id, status) in snapshot.watched { library.setWatchStatus(status, for: id) }
        pendingUndo = nil
        save()
        refreshDeck()
        flash("Reverted the last bulk change")
    }

    func openDeck(startAt video: Video) {
        let slides = visibleItems.map(\.deckSlide)
        guard !slides.isEmpty else { return }
        deckFilter = filter
        deckQuery = query
        deckTitle = filter.title
        deck = DeckModel(slides: slides, startAt: "v-\(video.id.uuidString)")
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

    func browsePlaylistCatalog() {
        select(.playlists)
    }

    /// Saves a fetched playlist as a course. Re-adding updates the chapter list
    /// while keeping ticks for chapters that still exist.
    /// `tags` nil keeps the current categories (used when refreshing); the import
    /// sheet always passes a reviewed list.
    @discardableResult
    func catalogPlaylist(_ metadata: PlaylistMetadata, tags: [String]? = nil) -> PlaylistRecord {
        if var existing = playlist(id: metadata.playlistID) {
            existing.title = metadata.title
            existing.channel = metadata.channel
            existing.replaceItems(metadata.items)
            existing.isTruncated = metadata.truncated
            if let tags { existing.tags = TagNormalizer.merge(tags) }
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
            isTruncated: metadata.truncated,
            tags: tags ?? []
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
        deck = DeckModel(
            slides: slides.map(DeckSlide.video),
            startAt: "v-\(first.id.uuidString)"
        )
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

    /// A course is judged by its title first, then by the chapters it contains.
    func suggestPlaylistTags(_ metadata: PlaylistMetadata) async -> TagSuggestion {
        let chapterContext = metadata.items.prefix(8).map(\.title).joined(separator: ". ")
        return await engine.suggest(
            title: metadata.title,
            channel: metadata.channel,
            description: chapterContext,
            channelHint: library.channelAffinity(for: metadata.channel),
            knownCategories: categoryChoices
        )
    }

    func setPlaylistTags(_ tags: [String], id: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].tags = TagNormalizer.merge(tags)
        savePlaylists()
        flash("Updated categories for \(playlists[index].title)")
    }

    func savePlaylists() {
        do {
            try playlistStore.save(playlists)
        } catch {
            flash("Could not save the playlist catalog: \(error.localizedDescription)")
        }
        scheduleSpotlight()
    }

    /// Spotlight results open a custom URL; route it to the shelf or the catalog.
    func handleURL(_ url: URL) {
        guard url.scheme == "tubeshelf" else { return }
        let id = url.lastPathComponent
        switch url.host {
        case "video":
            guard let video = library.video(youtubeID: id) else { return }
            filter = .all
            query = ""
            openDeck(startAt: video)
        case "playlist":
            openPlaylistCatalog(id: id)
        default:
            break
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

    func toggleChannelPin(_ name: String) {
        let isPinned = library.toggleChannelPin(name)
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
    var categoryHealth: CategoryAudit.Report {
        CategoryAudit.report(
            videoCounts: library.tagCounts,
            playlistTags: playlists.flatMap(\.tags),
            thinVideoCount: library.videos.filter { $0.tags.count <= 1 }.count,
            totalVideos: library.videos.count
        )
    }

    var categoryChoices: [String] {
        var names = library.tagCounts.map(\.name)
        for record in playlists {
            for tag in record.tags where !names.contains(where: {
                $0.caseInsensitiveCompare(tag) == .orderedSame
            }) {
                names.append(tag)
            }
        }
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

    /// Esc in the map: clear the category filter first, then return to the grid.
    func mapEscape() {
        if case .tag = filter {
            select(.all)
        } else {
            presentation = .grid
        }
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
            knownCategories: library.tagCounts.map(\.name),
            localAI: localAIConfig
        )
    }

    // MARK: - Backup

    @discardableResult
    func backup(to url: URL) throws -> Int {
        try BackupService().write(library, playlists: playlists, to: url)
        let snapshot = ShelfSnapshot(library: library, playlists: playlists)
        mergeBase = snapshot
        try? MergeBaseStore(directory: store.directory).save(snapshot)
        flash("Backed up \(library.count) video\(library.count == 1 ? "" : "s")")
        return library.count
    }

    /// The current profile as a merge input.
    var snapshot: ShelfSnapshot {
        ShelfSnapshot(library: library, playlists: playlists)
    }

    @discardableResult
    func restore(from url: URL) throws -> Int {
        let contents = try BackupService().readContents(from: url)
        replace(
            with: ShelfSnapshot(library: contents.library, playlists: contents.playlists),
            name: url.lastPathComponent
        )
        return contents.library.count
    }

    /// Replace the profile with a backup. The outgoing library and catalog are
    /// copied aside so a wrong file is always recoverable.
    func replace(with incoming: ShelfSnapshot, name: String) {
        writeAside()

        library = incoming.library
        playlists = incoming.playlists
        savePlaylists()
        filter = .all
        query = ""
        sidebarQuery = ""
        pageIndex = 0
        deck = nil
        editingVideoID = nil
        isAddPresented = false
        resetSelection()
        save()

        mergeBase = incoming
        try? MergeBaseStore(directory: store.directory).save(incoming)
        flash("Restored \(incoming.library.count) video\(incoming.library.count == 1 ? "" : "s")")
    }

    /// Apply a reviewed merge as one step. The merge base stays where it was:
    /// the incoming file is not an ancestor of the merged shelf.
    func applyMerge(_ merged: ShelfSnapshot, name: String) {
        let before = snapshot
        library = merged.library
        playlists = merged.playlists
        savePlaylists()
        deck = nil
        editingVideoID = nil
        isAddPresented = false
        resetSelection()
        save()
        flash("Merged \(name)", actionTitle: "Undo") { [weak self] in
            guard let self else { return }
            self.library = before.library
            self.playlists = before.playlists
            self.savePlaylists()
            self.save()
            self.flash("Merge undone")
        }
    }

    private func writeAside() {
        let stamp = Int(Date().timeIntervalSince1970)
        if let data = try? Data(contentsOf: store.fileURL) {
            let aside = store.directory.appendingPathComponent("library-before-restore-\(stamp).json")
            try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try? data.write(to: aside, options: .atomic)
        }
        if let playlistsData = try? Data(contentsOf: playlistStore.fileURL) {
            let aside = store.directory.appendingPathComponent("playlists-before-restore-\(stamp).json")
            try? playlistsData.write(to: aside, options: .atomic)
        }
    }

    // MARK: - Persistence

    func scheduleSpotlight() {
        SpotlightIndexer.shared.schedule(
            videos: library.videos,
            playlists: playlists,
            enabled: spotlightEnabled
        )
    }

    func save() {
        // A category can disappear when its last video is deleted or retagged;
        // drop the orphaned pin before it reaches disk. Courses count too.
        prunePins()
        if !selectedVideoIDs.isEmpty {
            selectedVideoIDs.formIntersection(Set(library.videos.map(\.id)))
        }
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
        scheduleSpotlight()
    }

    func flash(
        _ message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        toast = message
        toastActionTitle = actionTitle
        toastAction = action
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(action == nil ? 2.6 : 5.0))
            guard !Task.isCancelled else { return }
            self?.toast = nil
            self?.toastActionTitle = nil
            self?.toastAction = nil
        }
    }

    func refreshDeck() {
        guard var current = deck else { return }
        current.refresh(with: deckSlides(filter: deckFilter, query: deckQuery))
        if current.total == 0 {
            deck = nil
        } else {
            deck = current
        }
    }

    private func deckSlides(filter: ShelfFilter, query: String) -> [DeckSlide] {
        var items = library.videos(filter: filter, query: query, scope: searchScope).map(ShelfItem.video)
        if let tag = filter.tagName {
            items.append(contentsOf: playlistsTagged(tag, query: query).map(ShelfItem.playlist))
            items.sort { $0.addedAt > $1.addedAt }
        }
        return items.map(\.deckSlide)
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

    static var spotlightEnabled: Bool {
        get { defaults.object(forKey: "spotlightEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "spotlightEnabled") }
    }

    static var localAIEnabled: Bool {
        get { defaults.object(forKey: "localAIEnabled") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "localAIEnabled") }
    }

    static var localAIURL: String {
        get { defaults.string(forKey: "localAIURL") ?? "http://127.0.0.1:1976/v1" }
        set { defaults.set(newValue, forKey: "localAIURL") }
    }

    static var localAIModel: String {
        get { defaults.string(forKey: "localAIModel") ?? "system" }
        set { defaults.set(newValue, forKey: "localAIModel") }
    }

    static var presentation: ShelfPresentation {
        get { ShelfPresentation(rawValue: defaults.string(forKey: "shelfPresentation") ?? "") ?? .grid }
        set { defaults.set(newValue.rawValue, forKey: "shelfPresentation") }
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
