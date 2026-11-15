import SwiftUI
import TubeShelfCore

/// Bulk category entry: the same picker as everywhere else, applied to every
/// selected video at once.
struct BulkCategorySheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add categories")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Applies to \(model.selectedCount) selected video\(model.selectedCount == 1 ? "" : "s").")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 10) {
                if tags.isEmpty {
                    Text("Nothing chosen yet — pick a category, or type a new one.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                } else {
                    FlowWrap(items: tags) { tag in
                        TagChip(name: tag, isRemovable: true) {
                            tags.removeAll { $0 == tag }
                        }
                    }
                }

                CategoryPickerField(model: model, applied: tags, autoFocus: true) { tag in
                    tags = TagNormalizer.merge(tags + [tag])
                }
            }
            .padding(20)

            Divider().opacity(0.4)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tags.isEmpty ? "Add" : "Add to \(model.selectedCount)") {
                    for tag in tags { model.bulkAddTag(tag) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(tags.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 500)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
