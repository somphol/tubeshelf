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

/// Review a restore one difference at a time.
struct MergeReviewView: View {
    let model: AppModel
    let review: MergeReviewState

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var choices: [String: MergeChoice]
    @State private var pending: [String]
    @State private var order: [String]
    @State private var current: String?

    private let diffs: [MergeDiff]

    private struct MergeDiff: Identifiable {
        let id: String
        let conflict: MergeConflict
        let field: MergeFieldConflict?
    }

    init(model: AppModel, review: MergeReviewState) {
        self.model = model
        self.review = review
        let diffs = Self.makeDiffs(review.result)
        self.diffs = diffs
        _choices = State(initialValue: [:])
        _pending = State(initialValue: diffs.map(\.id))
        _order = State(initialValue: [])
        _current = State(initialValue: diffs.first?.id)
    }

    private static func makeDiffs(_ result: ShelfMergeResult) -> [MergeDiff] {
        var diffs: [MergeDiff] = []
        for conflict in result.conflicts {
            if conflict.fields.isEmpty {
                diffs.append(MergeDiff(
                    id: conflict.presenceKey,
                    conflict: conflict,
                    field: nil
                ))
            } else {
                for field in conflict.fields {
                    diffs.append(MergeDiff(
                        id: conflict.choiceKey(for: field),
                        conflict: conflict,
                        field: field
                    ))
                }
            }
        }
        return diffs
    }

    private var currentDiff: MergeDiff? {
        diffs.first { $0.id == current }
    }

    private var resolvedCount: Int {
        diffs.count - pending.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary
                    ProgressView(
                        value: Double(resolvedCount),
                        total: Double(max(diffs.count, 1))
                    )
                    .tint(Theme.accent)
                    Text("\(resolvedCount) of \(diffs.count) resolved · \(pending.count) left")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    toolbar
                    if pending.isEmpty {
                        donePanel
                    } else if let diff = currentDiff {
                        diffCard(diff)
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
        let count = diffs.count
        return VStack(alignment: .leading, spacing: 5) {
            if !parts.isEmpty {
                Text(parts.joined(separator: "  ·  "))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("\(count) difference\(count == 1 ? "" : "s") to review. One-sided backup changes are applied automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("A full backup is saved before and after merging.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button("Back") { back() }
                .disabled(order.isEmpty)
            Button("All This Mac") { setAll(.mine) }
            Button("All Backup") { setAll(.theirs) }
            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private var donePanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("All differences resolved", systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.green)
            Text("Press Merge to apply the choices. Use Back to revisit the last difference.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.green.opacity(0.3))
        )
    }

    private func diffCard(_ diff: MergeDiff) -> some View {
        let conflict = diff.conflict
        return VStack(alignment: .leading, spacing: 10) {
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

            if let field = diff.field {
                fieldChoices(diff, field)
            } else {
                presenceChoices(diff)
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

    private func fieldChoices(
        _ diff: MergeDiff,
        _ field: MergeFieldConflict
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(field.field.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                choiceCard(diff, .mine, "Keep This Mac", field.mine.displayText)
                choiceCard(diff, .theirs, "Use the Backup", field.theirs.displayText)
            }
            if let both = field.both {
                choiceCard(diff, .both, "Keep Both", both.displayText)
            }
        }
        .padding(.top, 4)
    }

    private func presenceChoices(_ diff: MergeDiff) -> some View {
        let conflict = diff.conflict
        let text = presenceText(conflict)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Deleted or changed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text.note)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                choiceCard(diff, .mine, text.mine, presenceDetail(conflict, .mine))
                choiceCard(diff, .theirs, text.theirs, presenceDetail(conflict, .theirs))
            }
        }
        .padding(.top, 4)
    }

    private func choiceCard(
        _ diff: MergeDiff,
        _ choice: MergeChoice,
        _ title: String,
        _ value: String
    ) -> some View {
        let selected = choices[diff.id] == choice
        return Button {
            resolve(diff, choice)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.accent)
                if !value.isEmpty {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.1) : Theme.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.hairline(scheme))
            )
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Cancel Merge") {
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
            Button {
                let merged = ShelfMerger.resolve(review.result, choices: choices)
                if model.applyMerge(merged, name: review.name, newBase: review.newBase) {
                    model.mergeReview = nil
                    dismiss()
                }
            } label: {
                Text(pending.isEmpty ? "Merge" : "Merge (\(pending.count) left)")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
            .disabled(!pending.isEmpty)
        }
        .padding(20)
    }

    private func resolve(_ diff: MergeDiff, _ choice: MergeChoice) {
        choices[diff.id] = choice
        if !order.contains(diff.id) {
            order.append(diff.id)
        }
        pending.removeAll { $0 == diff.id }
        current = pending.first
    }

    private func back() {
        guard let key = order.popLast() else { return }
        if !pending.contains(key) {
            pending.insert(key, at: 0)
        }
        current = key
    }

    private func setAll(_ choice: MergeChoice) {
        for diff in diffs {
            choices[diff.id] = choice
        }
        pending = []
        order = diffs.map(\.id)
        current = nil
    }

    private func presenceText(
        _ conflict: MergeConflict
    ) -> (note: String, mine: String, theirs: String) {
        if conflict.kind == .playlist, conflict.presence == .altered {
            return (
                "Changed in both places.",
                "Keep This Course",
                "Use the Backup"
            )
        }
        let noun = conflict.kind == .video ? "Video" : "Course"
        if conflict.presence == .deletedInBackup {
            return (
                "Deleted in the backup, edited here.",
                "Keep This \(noun)",
                "Use the Deletion"
            )
        }
        return (
            "Deleted here, edited in the backup.",
            "Keep It Deleted",
            "Bring It Back"
        )
    }

    private func presenceDetail(
        _ conflict: MergeConflict,
        _ choice: MergeChoice
    ) -> String {
        if conflict.presence == .deletedInBackup {
            if conflict.kind == .video {
                return choice == .mine ? "The edited video stays." : "The video is removed."
            }
            return choice == .mine
                ? (conflict.mineTitle ?? "The course stays.")
                : "The course is removed."
        }
        if conflict.presence == .deletedHere {
            if conflict.kind == .video {
                return choice == .mine ? "It stays removed." : "The backup copy returns."
            }
            return choice == .mine
                ? "It stays removed."
                : (conflict.theirsTitle ?? "The backup copy returns.")
        }
        if conflict.presence == .altered {
            return choice == .mine
                ? (conflict.mineTitle ?? "This Mac's course")
                : (conflict.theirsTitle ?? conflict.incomingPlaylist?.title ?? "The backup course")
        }
        return ""
    }
}
