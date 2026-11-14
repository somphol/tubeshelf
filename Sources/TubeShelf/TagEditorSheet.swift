import SwiftUI
import AppKit
import TubeShelfCore

struct TagEditorSheet: View {
    let model: AppModel
    let video: Video

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var note: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ThumbnailView(videoID: video.youtubeID, cornerRadius: 8)
                    .frame(width: 132)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit details")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text(video.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(video.channel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 16) {
                categories
                noteEditor
            }
            .padding(20)

            Divider().opacity(0.4)

            HStack {
                Button("Open on YouTube") { NSWorkspace.shared.open(video.watchURL) }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    model.setTags(tags, for: video.id)
                    model.setNote(note, for: video.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 13)
        }
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            tags = video.tags
            note = video.note
        }
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Categories")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("add more, or start a new one")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if tags.isEmpty {
                Text("No categories — this video sits in Unsorted.")
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

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Note")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            TextEditor(text: $note)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: 84)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
        }
    }

}
