import Foundation
import CoreSpotlight
import UniformTypeIdentifiers
import TubeShelfCore

/// Mirrors the shelf into Spotlight so ⌘Space can find a video or a course.
/// Debounced: a burst of edits reindexes once.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    private var pending: Task<Void, Never>?
    private let domain = "studio.somphol.tubeshelf"

    func schedule(videos: [Video], playlists: [PlaylistRecord], enabled: Bool) {
        pending?.cancel()
        pending = Task { [videos, playlists] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            await index(videos: videos, playlists: playlists, enabled: enabled)
        }
    }

    private func index(videos: [Video], playlists: [PlaylistRecord], enabled: Bool) async {
        do {
            try await deleteAll()
            guard enabled else { return }

            var items: [CSSearchableItem] = []
            for video in videos {
                let attributes = CSSearchableItemAttributeSet(contentType: .movie)
                attributes.title = video.title
                attributes.contentDescription = (
                    [video.channel] + video.tags + (video.note.isEmpty ? [] : [video.note])
                ).joined(separator: " · ")
                attributes.keywords = video.tags + [video.channel, "TubeShelf"]
                attributes.thumbnailURL = URL(string: "https://i.ytimg.com/vi/\(video.youtubeID)/hqdefault.jpg")
                attributes.contentURL = URL(string: "tubeshelf://video/\(video.youtubeID)")
                items.append(CSSearchableItem(
                    uniqueIdentifier: "video-\(video.youtubeID)",
                    domainIdentifier: domain,
                    attributeSet: attributes
                ))
            }

            for playlist in playlists {
                let attributes = CSSearchableItemAttributeSet(contentType: .content)
                attributes.title = playlist.title
                attributes.contentDescription = "Course · \(playlist.chapterCount) chapters · \(playlist.channel)"
                attributes.keywords = playlist.tags + [playlist.channel, "TubeShelf", "Playlist"]
                if let cover = playlist.coverVideoID {
                    attributes.thumbnailURL = URL(string: "https://i.ytimg.com/vi/\(cover)/hqdefault.jpg")
                }
                attributes.contentURL = URL(string: "tubeshelf://playlist/\(playlist.id)")
                items.append(CSSearchableItem(
                    uniqueIdentifier: "playlist-\(playlist.id)",
                    domainIdentifier: domain,
                    attributeSet: attributes
                ))
            }

            guard !items.isEmpty else { return }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                CSSearchableIndex.default().indexSearchableItems(items) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            NSLog("TubeShelf: Spotlight indexing failed — \(error.localizedDescription)")
        }
    }

    private func deleteAll() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            CSSearchableIndex.default().deleteAllSearchableItems { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
