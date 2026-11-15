import SwiftUI
import TubeShelfCore

/// Advisory view of the category list: merge candidates, one-item categories and
/// catch-alls. Nothing changes without an explicit press.
struct TidyView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var dialog: Dialog?

    private enum Dialog: Identifiable {
        case merge(source: String, target: String)
        case delete(String)

        var id: String {
            switch self {
            case .merge(let source, let target): "merge-\(source)-\(target)"
            case .delete(let name): "delete-\(name)"
            }
        }
    }

    private var report: CategoryAudit.Report { model.categoryHealth }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .frame(width: 580, height: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(dialogTitle, isPresented: Binding(
            get: { dialog != nil },
            set: { if !$0 { dialog = nil } }
        )) {
            switch dialog {
            case .merge(let source, let target):
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Merge") {
                    model.mergeCategories(source, into: target)
                    dialog = nil
                }
            case .delete(let name):
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Delete", role: .destructive) {
                    model.deleteTag(name)
                    dialog = nil
                }
            case .none:
                EmptyView()
            }
        } message: {
            Text(dialogMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tidy categories")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(report.totalCategories) categories · \(report.totalVideos) videos · \(report.thinVideoCount) with one tag or none")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Done") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(
                    title: "Merge candidates",
                    hint: "Names that look like the same category.",
                    empty: "No near-duplicates found.",
                    isEmpty: report.nearDuplicates.isEmpty
                ) {
                    ForEach(report.nearDuplicates) { pair in
                        pairRow(pair)
                    }
                }

                section(
                    title: "One-item categories",
                    hint: "A single video or course — maybe a category that never took off.",
                    empty: "Every category holds more than one item.",
                    isEmpty: report.lonely.isEmpty
                ) {
                    ForEach(report.lonely) { tag in
                        lonelyRow(tag)
                    }
                }

                section(
                    title: "Catch-alls",
                    hint: "Categories holding a third of the shelf or more.",
                    empty: "Nothing dominates the shelf.",
                    isEmpty: report.catchAlls.isEmpty
                ) {
                    ForEach(report.catchAlls) { tag in
                        catchAllRow(tag)
                    }
                }
            }
            .padding(20)
        }
    }

    private func section<Content: View>(
        title: String,
        hint: String,
        empty: String,
        isEmpty: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(hint)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)

            if isEmpty {
                Text(empty)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 2)
            } else {
                content()
            }
        }
    }

    private func pairRow(_ pair: CategoryPair) -> some View {
        let firstCount = report.counts.first { $0.name == pair.first }?.count ?? 0
        let secondCount = report.counts.first { $0.name == pair.second }?.count ?? 0
        // Keep the bigger category, absorb the smaller one.
        let target = firstCount >= secondCount ? pair.first : pair.second
        let source = firstCount >= secondCount ? pair.second : pair.first

        return HStack(spacing: 8) {
            Text(pair.first)
                .font(.system(size: 11.5, weight: .medium))
            Image(systemName: "arrow.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(pair.second)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Button("Merge into “\(target)”") {
                dialog = .merge(source: source, target: target)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func lonelyRow(_ tag: TagCount) -> some View {
        HStack(spacing: 8) {
            Text(tag.name)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Button("View") {
                model.select(.tag(tag.name))
                dismiss()
            }
            .controlSize(.small)
            Button("Delete", role: .destructive) {
                dialog = .delete(tag.name)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private func catchAllRow(_ tag: TagCount) -> some View {
        HStack(spacing: 8) {
            Text(tag.name)
                .font(.system(size: 11.5, weight: .medium))
            Text("\(tag.count)")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer()
            Button("View") {
                model.select(.tag(tag.name))
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(.vertical, 3)
    }

    private var footer: some View {
        HStack {
            Text("Nothing is changed until you press a button.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    private var dialogTitle: String {
        switch dialog {
        case .merge: "Merge categories?"
        case .delete: "Delete category?"
        case nil: ""
        }
    }

    private var dialogMessage: String {
        switch dialog {
        case .merge(let source, let target):
            let moved = report.counts.first { $0.name == source }?.count ?? 0
            return "\(moved) item\(moved == 1 ? "" : "s") move from “\(source)” into “\(target)”. No videos or courses are deleted."
        case .delete(let name):
            return "“\(name)” is removed from every video and course. The items themselves stay."
        case nil:
            return ""
        }
    }
}
