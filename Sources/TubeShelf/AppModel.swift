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
    var pageIndex = 0
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

    let store: LibraryStore
    let modelStatus: OnDeviceModelStatus
    private let engine = TagEngine()
    private var toastTask: Task<Void, Never>?
    private var deckFilter: ShelfFilter = .all
    private var deckQuery: String = ""

    /// Release builds always use the real Application Support folder; the debug
    /// snapshot mode can point at a throwaway library for scale testing.
    static func defaultStore() -> LibraryStore {
        #if DEBUG
        if let directory = SnapshotConfig.libraryDirectory {
            return LibraryStore(directory: directory)
        }
        #endif
        return LibraryStore()
    }

    init(store: LibraryStore) {
        self.store = store
        self.modelStatus = TagEngine.status
        self.categorySort = Preferences.categorySort
        self.categorySortAscending = Preferences.categorySortAscending
        self.searchScope = Preferences.searchScope
        self.library = Library()
        do {
            self.library = try store.load()
        } catch {
            self.library = Library()
            self.toast = "Could not read your library: \(error.localizedDescription)"
        }
    }

    // MARK: - Derived

    var visibleVideos: [Video] {
        library.videos(filter: filter, query: query, scope: searchScope)
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
            channelHint: library.channelAffinity(for: metadata.channel)
        )
    }

    // MARK: - Backup

    @discardableResult
    func backup(to url: URL) throws -> Int {
        try BackupService().write(library, to: url)
        flash("Backed up \(library.count) video\(library.count == 1 ? "" : "s")")
        return library.count
    }

    @discardableResult
    func restore(from url: URL) throws -> Int {
        let incoming = try BackupService().read(from: url)

        // Keep the outgoing library beside the store so choosing the wrong file
        // is always recoverable.
        if let data = try? Data(contentsOf: store.fileURL) {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = store.directory.appendingPathComponent("library-before-restore-\(stamp).json")
            try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            try? data.write(to: aside, options: .atomic)
        }

        library = incoming
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

    static var pageSize: Int {
        get {
            let stored = defaults.integer(forKey: "pageSize")
            return pageSizeOptions.contains(stored) ? stored : 48
        }
        set { defaults.set(newValue, forKey: "pageSize") }
    }
}
