import SwiftUI
import AppKit
import TubeShelfCore

/// Disk + memory cache for thumbnails. Downloads once, then the shelf and the
/// deck are instant even when YouTube is slow or offline.
actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let memory = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        directory = base
            .appendingPathComponent("TubeShelf", isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
        memory.countLimit = 300
    }

    func data(for videoID: String) async -> Data? {
        guard YouTubeURL.isVideoID(videoID) else { return nil }
        let key = videoID as NSString
        if let hit = memory.object(forKey: key) { return hit as Data }

        if let existing = inFlight[videoID] {
            return await existing.value
        }

        let task = Task<Data?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.download(videoID: videoID)
        }
        inFlight[videoID] = task
        let result = await task.value
        inFlight[videoID] = nil
        return result
    }

    func prefetch(videoID: String) async {
        _ = await data(for: videoID)
    }

    private func download(videoID: String) async -> Data? {
        let key = videoID as NSString
        let file = directory.appendingPathComponent("\(videoID).jpg")

        if let disk = try? Data(contentsOf: file), disk.count > 1_000 {
            memory.setObject(disk as NSData, forKey: key)
            return disk
        }

        for url in YouTubeURL.thumbnailCandidates(for: videoID) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            request.setValue("TubeShelf/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  data.count > 1_000
            else { continue }

            memory.setObject(data as NSData, forKey: key)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return data
        }
        return nil
    }
}

/// 16:9 artwork with a graceful placeholder, loaded off the main thread.
struct ThumbnailView: View {
    let videoID: String
    var aspectRatio: CGFloat = 16.0 / 9.0
    var cornerRadius: CGFloat = Theme.mediaRadius

    @State private var image: NSImage?
    @State private var didFail = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
            }
            .task(id: videoID) {
                didFail = false
                if let data = await ThumbnailCache.shared.data(for: videoID),
                   let decoded = NSImage(data: data) {
                    image = decoded
                } else {
                    didFail = true
                }
            }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(scheme == .dark ? 0.55 : 0.10),
                    Color.black.opacity(scheme == .dark ? 0.30 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: didFail ? "video.slash" : "play.rectangle")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.secondary)
        }
    }
}
