import SwiftUI
import TubeShelfCore

/// The full category workspace for one playlist item, before it is added.
/// Everything the normal editor offers is here: multiple categories, the
/// type-ahead field with "create …", and an on-demand suggestion that reads the
/// video's real description instead of only its title.
struct PlaylistItemEditorSheet: View {
    let model: AppModel
    let item: PlaylistItem
    let initialTags: [String]
    var primaryLabel: String = "Use These Categories"
    let onSave: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var suggestion: TagSuggestion?
    @State private var isSuggesting = false
    @State private var suggestionError = ""

    private let metadataService = YouTubeMetadataService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 14) {
                categories
                suggestions
            }
            .padding(20)

            Divider().opacity(0.4)

            HStack {
                Button("Open on YouTube") {
                    NSWorkspace.shared.open(YouTubeURL.watchURL(for: item.videoID))
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(primaryLabel) {
                    onSave(tags)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .frame(width: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { tags = initialTags }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(videoID: item.videoID, cornerRadius: 8)
                .frame(width: 150)
            VStack(alignment: .leading, spacing: 4) {
                Text("Categories for this video")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(item.channel)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if let duration = item.durationSeconds {
                        Text("·").foregroundStyle(.tertiary)
                        Text(format(duration))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if tags.isEmpty {
                Text("No categories yet — add one below, or create a new one.")
                    .font(.system(size: 11))
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
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("Suggestion", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let suggestion, !suggestion.tags.isEmpty {
                    Text(suggestion.source.label)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.violet)
                }
                Spacer()
                if isSuggesting {
                    ProgressView().controlSize(.mini)
                }
                Button("Suggest again") {
                    Task { await refine() }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
                .disabled(isSuggesting)
                .help("Reads this video's description and re-runs the classifier")
            }

            if !suggestionError.isEmpty {
                Text(suggestionError)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.orange)
            } else if let suggestion, !suggestion.tags.isEmpty {
                let extra = suggestion.tags.filter { tag in
                    !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
                }
                if extra.isEmpty {
                    Text("Every suggestion is already applied.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 5) {
                        ForEach(extra, id: \.self) { tag in
                            TagChip(name: tag, isSuggested: true) {
                                tags = TagNormalizer.merge(tags + [tag])
                            }
                        }
                    }
                }
            } else {
                Text("No suggestion yet. “Suggest again” reads the full description; the initial guess only had the title.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func format(_ seconds: Int) -> String {
        let hours = seconds / 3600, minutes = (seconds % 3600) / 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
            : String(format: "%d:%02d", minutes, seconds % 60)
    }

    private func refine() async {
        isSuggesting = true
        suggestionError = ""
        do {
            let metadata = try await metadataService.fetch(videoID: item.videoID)
            suggestion = await model.suggestTags(for: metadata)
        } catch {
            suggestionError = "Could not read this video's details: \(error.localizedDescription)"
        }
        isSuggesting = false
    }
}
