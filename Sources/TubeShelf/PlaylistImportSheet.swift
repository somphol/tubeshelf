import SwiftUI
import AppKit
import TubeShelfCore

/// Review a playlist before anything is filed. Categories are filled from the
/// same classifier the app uses and are editable per row — nothing is added with
/// tags you have not seen.
struct PlaylistImportSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var urlText = ""
    @State private var phase: Phase = .idle
    @State private var metadata: PlaylistMetadata?
    @State private var selection = Set<String>()
    @State private var tagsByVideo: [String: [String]] = [:]
    @State private var bulkTags: [String] = []
    @State private var isAdding = false
    @State private var editingItem: PlaylistItem?
    @State private var didAutofill = false
    @State private var errorMessage = ""

    private enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private let service = PlaylistService()

    private var onShelf: Set<String> {
        guard let metadata else { return [] }
        return Set(metadata.items.map(\.videoID).filter { model.library.contains(youtubeID: $0) })
    }

    private var newItems: [PlaylistItem] {
        metadata?.items.filter { !onShelf.contains($0.videoID) } ?? []
    }

    private var selectableIDs: Set<String> {
        Set(newItems.map(\.videoID))
    }

    private var allSelected: Bool {
        !selectableIDs.isEmpty && selection == selectableIDs
    }

    private var someSelected: Bool {
        !selection.isEmpty && !allSelected
    }

    private func toggleAll() {
        selection = allSelected ? [] : selectableIDs
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            urlRow
            Divider().opacity(0.3)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 780, height: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guard !didAutofill else { return }
            didAutofill = true

            if urlText.isEmpty, let prefill = model.playlistImportPrefill {
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
        .sheet(item: $editingItem) { item in
            PlaylistItemEditorSheet(
                model: model,
                item: item,
                initialTags: TagNormalizer.merge((tagsByVideo[item.videoID] ?? []) + bulkTags)
            ) { updated in
                tagsByVideo[item.videoID] = updated
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add a playlist")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("Public or unlisted playlists. Private ones (Watch later, Liked) cannot be read.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let metadata {
                Text("\(metadata.items.count) videos · \(onShelf.count) on shelf")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var urlRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("https://youtube.com/playlist?list=…", text: $urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .onSubmit { Task { await fetch() } }
            if phase == .loading {
                ProgressView().controlSize(.small)
            }
            Button("Fetch") { Task { await fetch() } }
                .controlSize(.small)
                .disabled(YouTubeURL.playlistID(from: urlText) == nil || phase == .loading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .idle:
            VStack(spacing: 10) {
                Image(systemName: "list.bullet.rectangle.portrait")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Paste a playlist link and press Fetch")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                Text("Nothing is added until you review the categories and confirm.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("Reading the playlist…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed:
            VStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Could not read that playlist")
                    .font(.system(size: 12.5, weight: .semibold))
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 400)
                Button("Try again") { Task { await fetch() } }
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .ready:
            VStack(spacing: 0) {
                selectionBar
                Divider().opacity(0.2)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(metadata?.items ?? []) { item in
                            row(item)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var selectionBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Button {
                    toggleAll()
                } label: {
                    Image(systemName: allSelected
                          ? "checkmark.square.fill"
                          : (someSelected ? "minus.square.fill" : "square"))
                        .font(.system(size: 13))
                        .foregroundStyle(allSelected || someSelected ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(allSelected ? "Deselect all" : "Select all")

                Text(metadata?.title ?? "Playlist")
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if metadata?.truncated == true {
                    Text("first batch only")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }

                Text("\(selection.count) of \(selectableIDs.count) selected")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)

                Spacer()
                Button("Select all") { selection = selectableIDs }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .disabled(allSelected || selectableIDs.isEmpty)
                Button("Deselect all") { selection.removeAll() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                    .disabled(selection.isEmpty)
            }

            HStack(spacing: 6) {
                Text("Add to every selected:")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)

                ForEach(bulkTags, id: \.self) { tag in
                    TagChip(name: tag, isRemovable: true) {
                        bulkTags.removeAll { $0 == tag }
                    }
                }

                CategoryPickerMenu(
                    title: "+ Category",
                    choices: model.categoryChoices,
                    applied: bulkTags
                ) { tag in
                    if !bulkTags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                        bulkTags = TagNormalizer.merge(bulkTags + [tag])
                    }
                }

                Spacer()

                Text("Categories are pre-filled; adjust any row.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private func row(_ item: PlaylistItem) -> some View {
        let already = onShelf.contains(item.videoID)
        let isSelected = selection.contains(item.videoID)
        let tags = TagNormalizer.merge((tagsByVideo[item.videoID] ?? []) + bulkTags)

        return HStack(spacing: 10) {
            Button {
                guard !already else { return }
                if isSelected { selection.remove(item.videoID) } else { selection.insert(item.videoID) }
            } label: {
                Image(systemName: already ? "checkmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 13))
                    .foregroundStyle(already ? Color.secondary : (isSelected ? Theme.accent : Color.secondary.opacity(0.5)))
            }
            .buttonStyle(.plain)
            .disabled(already)

            ThumbnailView(videoID: item.videoID, cornerRadius: 5)
                .frame(width: 78)
                .opacity(already ? 0.5 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(item.channel)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    if let duration = item.durationSeconds {
                        Text(format(duration))
                            .font(.system(size: 9.5).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 6)

            if already {
                Text("On shelf")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                Button {
                    editingItem = item
                } label: {
                    HStack(spacing: 4) {
                        if tags.isEmpty {
                            Text("No category")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        } else {
                            ForEach(tags.prefix(2), id: \.self) { tag in
                                Text(tag)
                                    .font(.system(size: 9.5, weight: .medium))
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.07), in: Capsule())
                            }
                            if tags.count > 2 {
                                Text("+\(tags.count - 2)")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: "pencil")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .opacity(isSelected ? 1 : 0.45)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit categories for this video")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .opacity(already ? 0.6 : 1)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(selection.isEmpty ? "Nothing selected yet" : "\(selection.count) selected · categories shown will be applied")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(isAdding ? "Adding…" : "Add \(selection.count) video\(selection.count == 1 ? "" : "s")") {
                addSelected()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(selection.isEmpty || isAdding)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func format(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60, secs = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    private func fetch() async {
        guard let id = YouTubeURL.playlistID(from: urlText) else {
            phase = .failed
            errorMessage = "That link has no playlist id. Copy it from the playlist page."
            return
        }

        phase = .loading
        errorMessage = ""
        do {
            let result = try await service.fetch(playlistID: id)
            metadata = result
            selection = Set(result.items.map(\.videoID).filter { !model.library.contains(youtubeID: $0) })

            // Pre-fill from the classifier so every row already shows its filing,
            // using the same matcher as the app (instant, no model round-trips).
            let known = model.library.tagCounts.map(\.name)
            var prefill: [String: [String]] = [:]
            for item in result.items {
                prefill[item.videoID] = HeuristicTagger().suggest(
                    title: item.title,
                    channel: item.channel,
                    limit: 3,
                    knownCategories: known
                ).tags
            }
            tagsByVideo = prefill
            phase = .ready
        } catch {
            phase = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func addSelected() {
        guard let metadata else { return }
        isAdding = true
        var final = tagsByVideo
        for id in selection {
            final[id] = TagNormalizer.merge((final[id] ?? []) + bulkTags)
        }
        model.importPlaylist(metadata, selection: selection, tagsByVideo: final)
        isAdding = false
        dismiss()
    }
}

/// Compact menu of every category, used for bulk application.
struct CategoryPickerMenu: View {
    let title: String
    let choices: [String]
    let applied: [String]
    let onPick: (String) -> Void

    var body: some View {
        Menu {
            ForEach(choices, id: \.self) { name in
                Button {
                    onPick(name)
                } label: {
                    if applied.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
