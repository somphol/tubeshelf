import SwiftUI
import AppKit
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
    @State private var addingItem: PlaylistItem?
    @State private var editingTags = false

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
        .sheet(isPresented: $editingTags) {
            PlaylistTagEditorSheet(model: model, record: playlist)
        }
        .sheet(item: $addingItem) { item in
            PlaylistItemEditorSheet(
                model: model,
                item: item,
                initialTags: model.suggestedTags(for: item),
                primaryLabel: "Add to Shelf"
            ) { tags in
                model.addChapterToShelf(item, tags: tags)
            }
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

                    HStack(spacing: 5) {
                        ForEach(playlist.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9.5, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.07), in: Capsule())
                        }
                        Button {
                            editingTags = true
                        } label: {
                            Label(playlist.tags.isEmpty ? "Add categories" : "Edit",
                                  systemImage: "tag")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.link)
                    }
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

                        if !onShelf {
                            Button {
                                addingItem = item
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                            .help("Add this chapter to your shelf — review its categories first")
                        }
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
                Button("Add missing to Shelf (\(missingCount))…") {
                    model.addMissingVideos(from: playlist)
                }
                .controlSize(.small)
                .help("Opens the review sheet for this playlist so you can choose categories before adding")
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
    @State private var tags: [String] = []
    @State private var suggestion: TagSuggestion?
    @State private var isSuggesting = false
    @State private var errorMessage = ""
    @State private var didAutofill = false

    private enum Phase: Equatable { case idle, loading, ready, failed }

    private let service = PlaylistService()

    private var existingRecord: PlaylistRecord? {
        guard let id = YouTubeURL.playlistID(from: urlText) else { return nil }
        return model.playlist(id: id)
    }

    private var alreadySaved: Bool { existingRecord != nil }

    /// Only meaningful once the fresh metadata has arrived.
    private var chapterDelta: Int? {
        guard let metadata, let existingRecord else { return nil }
        let delta = metadata.items.count - existingRecord.chapterCount
        return delta == 0 ? nil : delta
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

                if let existingRecord, existingRecord.id == YouTubeURL.playlistID(from: urlText) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Already in the catalog")
                                .font(.system(size: 11, weight: .semibold))
                            Text("\(existingRecord.chapterCount) chapters\(existingRecord.tags.isEmpty ? "" : " · " + existingRecord.tags.joined(separator: ", "))")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Open") {
                            let id = existingRecord.id
                            dismiss()
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(400))
                                model.openPlaylistCatalog(id: id)
                            }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.accent.opacity(0.08))
                    )
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text(metadata.title)
                                .font(.system(size: 13, weight: .semibold))
                            Text(metadata.channel.isEmpty ? "Playlist" : metadata.channel)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("\(metadata.items.count) chapters\(metadata.truncated ? " · first batch only" : "")")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                            ForEach(Array(metadata.items.prefix(2).enumerated()), id: \.element.videoID) { index, item in
                                Text("\(index + 1). \(item.title)")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if alreadySaved {
                                Text(chapterDelta.map { $0 > 0
                                     ? "Keeping it again adds \($0) new chapter\($0 == 1 ? "" : "s") and refreshes titles."
                                     : "Keeping it again refreshes titles and keeps your watched ticks."
                                } ?? "Keeping it again refreshes the chapter list and keeps your watched ticks.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Divider().opacity(0.3)

                            HStack(spacing: 6) {
                                Text("Categories")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                if isSuggesting {
                                    ProgressView().controlSize(.mini)
                                } else if let suggestion {
                                    Label(suggestion.source.label, systemImage: "sparkles")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(Theme.violet)
                                }
                                Spacer()
                            }

                            if tags.isEmpty {
                                Text("None yet — a suggestion will appear below.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                            } else {
                                FlowWrap(items: tags) { tag in
                                    TagChip(name: tag, isRemovable: true) {
                                        tags.removeAll { $0 == tag }
                                    }
                                }
                            }

                            CategoryPickerField(model: model, applied: tags) { tag in
                                tags = TagNormalizer.merge(tags + [tag])
                            }

                            if let suggestion {
                                let extra = suggestion.tags.filter { tag in
                                    !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                                }
                                if !extra.isEmpty {
                                    HStack(spacing: 5) {
                                        Text("Suggested")
                                            .font(.system(size: 9.5))
                                            .foregroundStyle(.tertiary)
                                        ForEach(extra, id: \.self) { tag in
                                            TagChip(name: tag, isSuggested: true) {
                                                tags = TagNormalizer.merge(tags + [tag])
                                            }
                                        }
                                    }
                                }
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
                        model.catalogPlaylist(metadata, tags: tags)
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
        .frame(width: 540, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !didAutofill else { return }
            didAutofill = true

            if urlText.isEmpty, let prefill = model.catalogPlaylistPrefill {
                urlText = prefill
                Task { await fetch() }
                return
            }
            if urlText.isEmpty,
               let clip = NSPasteboard.general.string(forType: .string),
               YouTubeURL.playlistID(from: clip) != nil {
                urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { await fetch() }
            }
        }
    }

    private func fetch() async {
        guard let id = YouTubeURL.playlistID(from: urlText) else {
            phase = .failed
            errorMessage = "That link has no playlist id."
            return
        }
        phase = .loading
        suggestion = nil
        do {
            let fetched = try await service.fetch(playlistID: id)
            metadata = fetched
            phase = .ready

            // Keep existing categories when re-keeping a course; otherwise ask the
            // classifier, which reads the title and the first chapters.
            if let existing = model.playlist(id: fetched.playlistID) {
                tags = existing.tags
            } else {
                isSuggesting = true
                let suggested = await model.suggestPlaylistTags(fetched)
                suggestion = suggested
                if tags.isEmpty { tags = suggested.tags }
                isSuggesting = false
            }
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }
}
