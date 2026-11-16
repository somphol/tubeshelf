import SwiftUI
import TubeShelfCore

struct MergeReviewState: Identifiable {
    let id = UUID()
    var result: ShelfMergeResult
    var incoming: ShelfSnapshot
    var name: String
    /// Set after a first merge with no ancestor: the incoming file becomes the base.
    var newBase: ShelfSnapshot? = nil
}

/// Review a restore that overlaps edits already made on this Mac.
struct MergeReviewView: View {
    let model: AppModel
    let review: MergeReviewState

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var choices: [String: MergeChoice]

    init(model: AppModel, review: MergeReviewState) {
        self.model = model
        self.review = review
        var defaults: [String: MergeChoice] = [:]
        for conflict in review.result.conflicts {
            if conflict.fields.isEmpty {
                defaults[conflict.presenceKey] = conflict.defaultChoice
            } else {
                for field in conflict.fields {
                    defaults[conflict.choiceKey(for: field)] = field.defaultChoice
                }
            }
        }
        _choices = State(initialValue: defaults)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summary
                    bulkActions
                    ForEach(review.result.conflicts) { conflict in
                        card(conflict)
                    }
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(minWidth: 660, idealWidth: 720, minHeight: 560, idealHeight: 640)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Merge backup")
                    .font(.title3.weight(.semibold))
                Text(review.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                model.mergeReview = nil
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .help("Close (esc)")
        }
        .padding(20)
    }

    private var summary: some View {
        let stats = review.result.stats
        var parts: [String] = []
        if stats.added > 0 { parts.append("\(stats.added) added") }
        if stats.updated > 0 { parts.append("\(stats.updated) updated") }
        if stats.deleted > 0 { parts.append("\(stats.deleted) removed") }
        if stats.kept > 0 { parts.append("\(stats.kept) kept locally") }
        let count = review.result.conflicts.count
        return VStack(alignment: .leading, spacing: 5) {
            if !parts.isEmpty {
                Text(parts.joined(separator: "  ·  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("\(count) conflict\(count == 1 ? "" : "s") need\(count == 1 ? "s" : "") a choice. Other backup changes are applied automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("A full backup is saved before and after merging.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var bulkActions: some View {
        HStack(spacing: 8) {
            Button("All This Mac") { setAll(.mine) }
            Button("All Backup") { setAll(.theirs) }
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private func card(_ conflict: MergeConflict) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(conflict.title)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(conflict.kind == .video ? "Video" : "Course")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.14)))
                    .foregroundStyle(Theme.accent)
            }

            if conflict.fields.isEmpty {
                presenceRow(conflict)
            } else {
                ForEach(conflict.fields) { field in
                    fieldRow(conflict, field)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.hairline(scheme))
        )
    }

    private func fieldRow(_ conflict: MergeConflict, _ field: MergeFieldConflict) -> some View {
        let chosen = choices[conflict.choiceKey(for: field)] ?? field.defaultChoice
        return VStack(alignment: .leading, spacing: 6) {
            Text(field.field.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("", selection: binding(conflict, field)) {
                Text("This Mac").tag(MergeChoice.mine)
                Text("Backup").tag(MergeChoice.theirs)
                if field.both != nil {
                    Text("Both").tag(MergeChoice.both)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Theme.accent)

            valueLine("This Mac", field.mine.displayText)
            valueLine("Backup", field.theirs.displayText)
            if chosen == .both, let both = field.both {
                valueLine("Both", both.displayText)
            }
        }
        .padding(.top, 8)
    }

    private func presenceRow(_ conflict: MergeConflict) -> some View {
        let text = presenceText(conflict)
        return VStack(alignment: .leading, spacing: 6) {
            Text(text.note)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let mine = conflict.mineTitle, let theirs = conflict.theirsTitle {
                valueLine("This Mac", mine)
                valueLine("Backup", theirs)
            }
            Picker("", selection: presenceBinding(conflict)) {
                Text(text.mine).tag(MergeChoice.mine)
                Text(text.theirs).tag(MergeChoice.theirs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(Theme.accent)
        }
        .padding(.top, 4)
    }

    private func valueLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(label):")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Keep This Mac") {
                model.mergeReview = nil
                dismiss()
            }
            Spacer()
            Button("Use Backup Instead") {
                if model.replace(with: review.incoming, name: review.name) {
                    model.mergeReview = nil
                    dismiss()
                }
            }
            .foregroundStyle(.red)
            Button("Merge") {
                let merged = ShelfMerger.resolve(review.result, choices: choices)
                if model.applyMerge(merged, name: review.name, newBase: review.newBase) {
                    model.mergeReview = nil
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func binding(_ conflict: MergeConflict, _ field: MergeFieldConflict) -> Binding<MergeChoice> {
        Binding(
            get: { choices[conflict.choiceKey(for: field)] ?? field.defaultChoice },
            set: { choices[conflict.choiceKey(for: field)] = $0 }
        )
    }

    private func presenceBinding(_ conflict: MergeConflict) -> Binding<MergeChoice> {
        Binding(
            get: { choices[conflict.presenceKey] ?? conflict.defaultChoice },
            set: { choices[conflict.presenceKey] = $0 }
        )
    }

    private func setAll(_ choice: MergeChoice) {
        for conflict in review.result.conflicts {
            if conflict.fields.isEmpty {
                choices[conflict.presenceKey] = choice
            } else {
                for field in conflict.fields {
                    choices[conflict.choiceKey(for: field)] = choice
                }
            }
        }
    }

    private func presenceText(
        _ conflict: MergeConflict
    ) -> (note: String, mine: String, theirs: String) {
        if conflict.kind == .playlist, conflict.presence == .altered {
            return ("Changed in both places.", "This Mac", "Backup")
        }
        if conflict.presence == .deletedInBackup {
            return ("Deleted in the backup, edited here.", "Keep Deleted", "Restore")
        }
        return ("Deleted here, edited in the backup.", "Keep Deleted", "Bring Back")
    }
}
