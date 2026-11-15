import SwiftUI
import AppKit
import TubeShelfCore

struct AddVideoSheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String = ""
    @State private var phase: Phase = .idle
    @State private var metadata: VideoMetadata?
    @State private var tags: [String] = []
    @State private var suggestion: TagSuggestion?
    @State private var isClassifying = false
    @State private var note: String = ""
    @State private var duplicateVideo: Video?

    private let service = YouTubeMetadataService()
    private let engine = TagEngine()

    private enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private var resolvedID: String? { YouTubeURL.videoID(from: urlText) }
    private var canSave: Bool { phase == .ready && metadata != nil }

    /// A duplicate is editable; the button only enables when something changed.
    private var hasChanges: Bool {
        guard let existing = duplicateVideo else { return true }
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return TagNormalizer.merge(tags) != existing.tags || cleanedNote != existing.note
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    urlField
                    preview
                    categorySection
                    noteField
                }
                .padding(22)
            }
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 680, height: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .task(id: urlText) {
            await debounceResolve()
        }
        .onAppear {
            if urlText.isEmpty, let clip = NSPasteboard.general.string(forType: .string),
               YouTubeURL.videoID(from: clip) != nil {
                urlText = clip
            }
            if let existing = pendingDuplicate() {
                duplicateVideo = existing
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            LogoMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Save a video")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Paste a YouTube link — the title and categories fill in automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    // MARK: - URL

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("https://youtube.com/watch?v=…", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit { Task { await resolve(force: true) } }
                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        resetPreview()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                if phase == .loading {
                    ProgressView().controlSize(.small)
                }
                Button("Paste") {
                    if let clip = NSPasteboard.general.string(forType: .string) {
                        urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        resolvedID == nil && !urlText.isEmpty
                            ? Color.orange.opacity(0.6)
                            : Color.primary.opacity(0.07),
                        lineWidth: 1
                    )
            )

            if !urlText.isEmpty, resolvedID == nil {
                Text("That is not a YouTube link. Watch, share, Shorts and youtu.be links all work.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        switch phase {
        case .idle:
            if urlText.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "command")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    Text("Focus the field above and press ⌘V. Nothing is fetched until a valid link is in place.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .loading:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Fetching title and thumbnail from YouTube…")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Could not load that video")
                        .font(.system(size: 12, weight: .semibold))
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Try again") { Task { await resolve(force: true) } }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
        case .ready:
            if let metadata {
                HStack(alignment: .top, spacing: 14) {
                    ThumbnailView(videoID: metadata.videoID)
                        .frame(width: 220)
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(metadata.title)
                            .font(.system(size: 13.5, weight: .semibold))
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(metadata.channel)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if let seconds = metadata.durationSeconds, seconds > 0 {
                                let hours = seconds / 3600
                                let minutes = (seconds % 3600) / 60
                                Text(hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
                                               : String(format: "%d:%02d", minutes, seconds % 60))
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                            }
                            Text("youtu.be/\(metadata.videoID)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        if let duplicateVideo {
                            VStack(alignment: .leading, spacing: 3) {
                                Label("Already on your shelf", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("Editing here updates the saved video — categories and note — instead of adding a duplicate.")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    model.revealVideo(duplicateVideo)
                                    dismiss()
                                } label: {
                                    Label("Show it on the shelf", systemImage: "arrow.uturn.backward")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .buttonStyle(.link)
                            }
                            .padding(.top, 4)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Categories

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                Text("Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                if isClassifying {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("classifying…").font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                } else if let suggestion, !suggestion.tags.isEmpty {
                    Label(suggestion.source.label, systemImage: suggestion.source == .onDeviceModel || suggestion.source == .localModel ? "sparkles" : "text.magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.violet)
                }
                Spacer()
                if !tags.isEmpty {
                    Button("Clear") { tags = [] }
                        .buttonStyle(.link)
                        .font(.system(size: 10))
                }
            }

            if tags.isEmpty {
                Text(hasSuggestion
                     ? "Nothing applied yet — tap a suggestion, or add one below."
                     : "No confident category — pick one below, or create a new one.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                FlowWrap(items: tags) { tag in
                    TagChip(name: tag, isRemovable: true) {
                        tags.removeAll { $0 == tag }
                    }
                }
            }

            if let suggestion, !suggestion.tags.isEmpty {
                let extra = suggestion.tags.filter { !tags.contains($0) }
                if !extra.isEmpty {
                    HStack(spacing: 5) {
                        Text("Suggested")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        ForEach(extra, id: \.self) { tag in
                            TagChip(name: tag, isSuggested: true) {
                                withAnimation(.easeOut(duration: 0.15)) {
                                    tags = TagNormalizer.merge(tags + [tag])
                                }
                            }
                        }
                    }
                }
            }

            CategoryPickerField(model: model, applied: tags) { tag in
                withAnimation(.easeOut(duration: 0.15)) {
                    tags = TagNormalizer.merge(tags + [tag])
                }
            }
        }
    }

    private var hasSuggestion: Bool {
        !(suggestion?.tags.isEmpty ?? true)
    }

    // MARK: - Note

    private var noteField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Why you saved it")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextField("Optional — searchable later", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .lineLimit(2...4)
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if let duplicateVideo {
                Text(hasChanges
                     ? "Saving updates “\(duplicateVideo.title)”"
                     : "No changes to “\(duplicateVideo.title)”")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(duplicateVideo == nil ? "Add to shelf" : "Update video") { save() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || !hasChanges)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 13)
    }

    // MARK: - Behaviour

    private func debounceResolve() async {
        guard let id = resolvedID else {
            resetPreview()
            return
        }
        if metadata?.videoID == id, phase == .ready { return }

        // Let the person finish pasting before hitting the network.
        try? await Task.sleep(for: .milliseconds(420))
        guard !Task.isCancelled else { return }
        await resolve(id: id)
    }

    private func resolve(id: String? = nil, force: Bool = false) async {
        guard let videoID = id ?? resolvedID else { return }
        if !force, metadata?.videoID == videoID, phase == .ready { return }

        phase = .loading
        metadata = nil
        suggestion = nil
        duplicateVideo = model.library.video(youtubeID: videoID)
        // Editing a saved video starts from what it already has, so updating
        // categories cannot silently wipe the ones on disk.
        tags = duplicateVideo?.tags ?? []
        note = duplicateVideo?.note ?? ""

        do {
            let fetched = try await service.fetch(videoID: videoID)
            guard !Task.isCancelled else { return }
            metadata = fetched
            phase = .ready
            duplicateVideo = model.library.video(youtubeID: videoID)

            isClassifying = true
            let suggestion = await engine.suggest(
                title: fetched.title,
                channel: fetched.channel,
                description: fetched.description
            )
            guard !Task.isCancelled else { return }
            self.suggestion = suggestion
            isClassifying = false
            if tags.isEmpty, duplicateVideo == nil {
                withAnimation(.easeOut(duration: 0.2)) {
                    tags = suggestion.tags
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }

    private func resetPreview() {
        phase = .idle
        metadata = nil
        tags = []
        suggestion = nil
        duplicateVideo = nil
        isClassifying = false
    }

    private func pendingDuplicate() -> Video? {
        guard let id = resolvedID else { return nil }
        return model.library.video(youtubeID: id)
    }

    private func save() {
        guard let metadata else { return }
        let finalTags = tags
        let cleanedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = duplicateVideo {
            var updated = existing
            updated.title = metadata.title
            updated.channel = metadata.channel
            updated.tags = TagNormalizer.merge(finalTags)
            updated.note = cleanedNote
            if let duration = metadata.durationSeconds {
                updated.durationSeconds = duration
            }
            model.updateVideo(updated)
            dismiss()
            return
        }

        let video = Video(
            youtubeID: metadata.videoID,
            title: metadata.title,
            channel: metadata.channel,
            tags: finalTags,
            note: cleanedNote,
            durationSeconds: metadata.durationSeconds
        )
        if model.add(video) {
            dismiss()
        }
    }
}

/// Simple wrapping layout for chips. SwiftUI's `Layout` protocol keeps this from
/// needing a fixed number of columns.
struct FlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        FlowLayout(spacing: 5) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
