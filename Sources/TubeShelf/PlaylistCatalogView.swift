import SwiftUI
import TubeShelfCore

/// The catalog of playlists — courses kept as ordered chapters, independent of
/// what is on the shelf.
struct PlaylistCatalogView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var showAdd = false

    var body: some View {
        Group {
            if let id = selectedID, let record = model.playlist(id: id) {
                PlaylistDetailView(
                    model: model,
                    playlist: record,
                    onBack: { selectedID = nil },
                    onRemoved: { selectedID = nil }
                )
            } else {
                catalog
            }
        }
        .frame(width: 660, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let pending = model.pendingPlaylistID {
                selectedID = pending
                model.pendingPlaylistID = nil
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPlaylistToCatalogSheet(model: model)
        }
    }

    private var catalog: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Playlists")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("\(model.playlists.count) courses · chapters stay in order · shelf is untouched")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Playlist…") { showAdd = true }
                    .controlSize(.small)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider().opacity(0.4)

            if model.playlists.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No playlists yet")
                        .font(.system(size: 13, weight: .medium))
                    Text("Keep a public playlist as a course, without adding its videos.\n⇧⌘⌥N from anywhere.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Add a Playlist…") { showAdd = true }
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.playlists) { record in
                            Button {
                                selectedID = record.id
                            } label: {
                                row(record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private func row(_ record: PlaylistRecord) -> some View {
        HStack(spacing: 12) {
            if let cover = record.coverVideoID {
                ThumbnailView(videoID: cover, cornerRadius: 6)
                    .frame(width: 96)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 96, height: 54)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(record.channel.isEmpty ? "Playlist" : record.channel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(record.chapterCount) chapters")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if record.isTruncated {
                        Text("first batch only")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                    }
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(record.watchedCount) / \(record.chapterCount)")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 84, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(2, 84 * record.progress), height: 4)
                    }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

struct PlaylistDetailView: View {
    let model: AppModel
    let playlist: PlaylistRecord
    let onBack: () -> Void
    let onRemoved: () -> Void

    @State private var confirmRemove = false

    private var onShelfCount: Int {
        playlist.items.filter { model.library.contains(youtubeID: $0.videoID) }.count
    }

    private var missingCount: Int { playlist.chapterCount - onShelfCount }

    private var coverVideoID: String? { playlist.coverVideoID }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            chapters
            Divider().opacity(0.4)
            footer
        }
        .alert("Remove from the catalog?", isPresented: $confirmRemove) {
            Button("Cancel", role: .cancel) {}
            Button("Remove", role: .destructive) {
                model.removePlaylist(id: playlist.id)
                onRemoved()
            }
        } message: {
            Text("The playlist disappears from the catalog. Its videos, if any, stay on the shelf.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button {
                    onBack()
                } label: {
                    Label("Playlists", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Open on YouTube") {
                    if let url = playlist.shareURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            HStack(alignment: .top, spacing: 12) {
                if let cover = coverVideoID {
                    ThumbnailView(videoID: cover, cornerRadius: 8)
                        .frame(width: 132)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text(playlist.channel.isEmpty ? "Playlist" : playlist.channel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text("\(playlist.watchedCount) of \(playlist.chapterCount) watched · \(onShelfCount) on shelf")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(Theme.accent)
                                .frame(width: max(2, 260 * playlist.progress), height: 4)
                        }
                        .frame(width: 260)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var chapters: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(playlist.items.enumerated()), id: \.element.videoID) { index, item in
                    let onShelf = model.library.contains(youtubeID: item.videoID)
                    let watched = playlist.isWatched(item.videoID)

                    HStack(spacing: 10) {
                        Text("\(index + 1)")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 20, alignment: .trailing)

                        Button {
                            model.toggleChapter(playlistID: playlist.id, videoID: item.videoID)
                        } label: {
                            Image(systemName: watched ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 13))
                                .foregroundStyle(watched ? Theme.accent : Color.secondary.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .help(watched ? "Mark chapter unwatched" : "Mark chapter watched")

                        ThumbnailView(videoID: item.videoID, cornerRadius: 4)
                            .frame(width: 64)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 11.5, weight: .medium))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                if let duration = item.durationSeconds {
                                    Text(format(duration))
                                        .font(.system(size: 9.5).monospacedDigit())
                                }
                                if onShelf {
                                    Text("On shelf").font(.system(size: 9))
                                } else {
                                    Text("Not on shelf").font(.system(size: 9))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Remove…", role: .destructive) { confirmRemove = true }
                .controlSize(.small)
                .foregroundStyle(.red)
            Spacer()
            if missingCount > 0 {
                Button("Add missing (\(missingCount))") {
                    model.addMissingVideos(from: playlist)
                }
                .controlSize(.small)
                .help("Opens the review sheet with this playlist so you can choose categories first")
            }
            Button("Present \(onShelfCount) chapter\(onShelfCount == 1 ? "" : "s")") {
                model.presentPlaylist(playlist)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.small)
            .disabled(onShelfCount == 0)
            .help("Walks the deck in playlist order, using chapters that are on the shelf")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private func format(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }
}

/// "Keep as a playlist": fetch, confirm, store. Adds no videos.
struct AddPlaylistToCatalogSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var phase: Phase = .idle
    @State private var metadata: PlaylistMetadata?
    @State private var errorMessage = ""

    private enum Phase: Equatable { case idle, loading, ready, failed }

    private let service = PlaylistService()

    private var alreadySaved: Bool {
        guard let metadata else { return false }
        return model.playlist(id: metadata.playlistID) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a playlist to the catalog")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Keeps the course and its chapter order. Adds no videos to your shelf.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    TextField("https://youtube.com/playlist?list=…", text: $urlText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit { Task { await fetch() } }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                    if phase == .loading { ProgressView().controlSize(.small) }
                    Button("Fetch") { Task { await fetch() } }
                        .controlSize(.small)
                        .disabled(YouTubeURL.playlistID(from: urlText) == nil || phase == .loading)
                }

                switch phase {
                case .idle:
                    Text("Public or unlisted playlists only.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                case .loading:
                    Text("Reading the playlist…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                case .failed:
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                case .ready:
                    if let metadata {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(metadata.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(metadata.channel.isEmpty ? "Playlist" : metadata.channel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("\(metadata.items.count) chapters\(metadata.truncated ? " · first batch only" : "")")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            ForEach(Array(metadata.items.prefix(3).enumerated()), id: \.element.videoID) { index, item in
                                Text("\(index + 1). \(item.title)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if alreadySaved {
                                Text("Already in the catalog — keeping it again updates the chapters.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider().opacity(0.4)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(alreadySaved ? "Update Chapters" : "Keep in Catalog") {
                    if let metadata {
                        model.catalogPlaylist(metadata)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(phase != .ready)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func fetch() async {
        guard let id = YouTubeURL.playlistID(from: urlText) else {
            phase = .failed
            errorMessage = "That link has no playlist id."
            return
        }
        phase = .loading
        do {
            metadata = try await service.fetch(playlistID: id)
            phase = .ready
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }
}
