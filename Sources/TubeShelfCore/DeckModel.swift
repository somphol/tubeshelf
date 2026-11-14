import Foundation

/// Slide-deck navigation over an already-filtered list of videos. Kept pure so
/// arrow keys, the filmstrip and the progress bar cannot disagree.
public struct DeckModel: Equatable, Sendable {
    public private(set) var slides: [Video]
    public private(set) var index: Int

    public init(slides: [Video], startAt videoID: UUID? = nil) {
        self.slides = slides
        if let videoID, let position = slides.firstIndex(where: { $0.id == videoID }) {
            self.index = position
        } else {
            self.index = 0
        }
    }

    public var current: Video? {
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

    public mutating func jump(to videoID: UUID) {
        guard let position = slides.firstIndex(where: { $0.id == videoID }) else { return }
        index = position
    }

    /// Keep the deck in sync when the underlying shelf changes (a tag was edited
    /// or a video removed while the deck is open).
    public mutating func refresh(with videos: [Video]) {
        let currentID = current?.id
        slides = videos
        if let currentID, let position = videos.firstIndex(where: { $0.id == currentID }) {
            index = position
        } else {
            index = min(index, max(0, videos.count - 1))
        }
    }
}
