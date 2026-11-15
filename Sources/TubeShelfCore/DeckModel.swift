import Foundation

/// One slide in the deck: a single video, or a whole course presented as a poster.
public enum DeckSlide: Identifiable, Equatable, Sendable {
    case video(Video)
    case playlist(PlaylistRecord)

    public var id: String {
        switch self {
        case .video(let video): "v-\(video.id.uuidString)"
        case .playlist(let playlist): "p-\(playlist.id)"
        }
    }

    public var title: String {
        switch self {
        case .video(let video): video.title
        case .playlist(let playlist): playlist.title
        }
    }

    public var thumbnailVideoID: String? {
        switch self {
        case .video(let video): video.youtubeID
        case .playlist(let playlist): playlist.coverVideoID
        }
    }

    public var video: Video? {
        if case .video(let video) = self { return video }
        return nil
    }

    public var playlist: PlaylistRecord? {
        if case .playlist(let playlist) = self { return playlist }
        return nil
    }
}

/// Slide-deck navigation over an already-filtered list of slides. Kept pure so
/// arrow keys, the filmstrip and the progress bar cannot disagree.
public struct DeckModel: Equatable, Sendable {
    public private(set) var slides: [DeckSlide]
    public private(set) var index: Int

    public init(slides: [DeckSlide], startAt slideID: String? = nil) {
        self.slides = slides
        if let slideID, let position = slides.firstIndex(where: { $0.id == slideID }) {
            self.index = position
        } else {
            self.index = 0
        }
    }

    /// Convenience for video-only decks (chapters, a category with no courses).
    public init(slides videos: [Video], startAt videoID: UUID? = nil) {
        self.init(
            slides: videos.map(DeckSlide.video),
            startAt: videoID.map { "v-\($0.uuidString)" }
        )
    }

    public var current: DeckSlide? {
        guard slides.indices.contains(index) else { return nil }
        return slides[index]
    }

    public var position: Int { slides.isEmpty ? 0 : index + 1 }
    public var total: Int { slides.count }
    public var isFirst: Bool { index <= 0 }
    public var isLast: Bool { index >= slides.count - 1 }
    public var progress: Double {
        guard total > 0 else { return 0 }
        return Double(position) / Double(total)
    }

    @discardableResult
    public mutating func showNext() -> Bool {
        guard index + 1 < slides.count else { return false }
        index += 1
        return true
    }

    @discardableResult
    public mutating func showPrevious() -> Bool {
        guard index > 0 else { return false }
        index -= 1
        return true
    }

    public mutating func jumpToFirst() {
        index = 0
    }

    public mutating func jumpToLast() {
        index = max(0, slides.count - 1)
    }

    public mutating func jump(to slideID: String) {
        guard let position = slides.firstIndex(where: { $0.id == slideID }) else { return }
        index = position
    }

    /// Keep the deck in sync when the underlying shelf changes.
    public mutating func refresh(with slides: [DeckSlide]) {
        let currentID = current?.id
        self.slides = slides
        if let currentID, let position = slides.firstIndex(where: { $0.id == currentID }) {
            index = position
        } else {
            index = min(index, max(0, slides.count - 1))
        }
    }

    public mutating func refresh(with videos: [Video]) {
        refresh(with: videos.map(DeckSlide.video))
    }
}
