import SwiftUI
import TubeShelfCore

/// Categories for a course. The same picker as videos, so courses can share
/// categories with videos and appear beside them in a category view.
struct PlaylistTagEditorSheet: View {
    let model: AppModel
    let record: PlaylistRecord

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                if let cover = record.coverVideoID {
                    ThumbnailView(videoID: cover, cornerRadius: 8)
                        .frame(width: 120)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Categories for this course")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(record.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(record.chapterCount) chapters · \(record.channel)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(20)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                if tags.isEmpty {
                    Text("No categories yet — courses appear beside videos when they share one.")
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
            .padding(20)

            Divider().opacity(0.4)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Categories") {
                    model.setPlaylistTags(tags, id: record.id)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { tags = record.tags }
    }
}
