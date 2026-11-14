import SwiftUI
import AppKit
import TubeShelfCore

/// Browse every category at scale: search, sort by video count or name, pin,
/// rename, merge and delete without hunting through the sidebar.
struct CategoryManagerView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hovering: String?
    @State private var renameText = ""
    @State private var dialog: ManagerDialog?

    private enum ManagerDialog: Identifiable {
        case rename(String)
        case delete(String)
        case merge(String, String)

        var id: String {
            switch self {
            case .rename(let name): "rename-\(name)"
            case .delete(let name): "delete-\(name)"
            case .merge(let source, let target): "merge-\(source)-\(target)"
            }
        }
    }

    private var allCounts: [TagCount] {
        model.library.tagCounts(sortedBy: model.categorySort, ascending: model.categorySortAscending)
    }

    private var rows: [TagCount] {
        let needle = SearchText.normalize(query)
        guard !needle.isEmpty else { return allCounts }
        return allCounts.filter { SearchText.matches(needle: needle, haystack: $0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            toolbar
            Divider().opacity(0.3)
            list
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
            case .rename(let current):
                TextField("Category name", text: $renameText)
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Rename") {
                    model.renameTag(current, to: renameText)
                    dialog = nil
                }
            case .delete(let name):
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Delete", role: .destructive) {
                    model.deleteTag(name)
                    dialog = nil
                }
            case .merge(let source, let target):
                Button("Cancel", role: .cancel) { dialog = nil }
                Button("Merge") {
                    model.mergeCategories(source, into: target)
                    dialog = nil
                }
            case .none:
                EmptyView()
            }
        } message: {
            Text(dialogMessage)
        }
    }

    private var sortChoice: Binding<SortChoice> {
        Binding(
            get: { SortChoice(sort: model.categorySort, ascending: model.categorySortAscending) },
            set: { choice in
                model.categorySort = choice.sort
                model.categorySortAscending = choice.ascending
            }
        )
    }

    private var dialogTitle: String {
        switch dialog {
        case .rename: "Rename category"
        case .delete: "Delete category?"
        case .merge: "Merge categories?"
        case nil: ""
        }
    }

    private var dialogMessage: String {
        switch dialog {
        case .rename:
            return "Every video filed here moves with it. Pins follow the new name."
        case .delete(let name):
            return "“\(name)” is removed from every video. The videos stay on the shelf."
        case .merge(let source, let target):
            let moved = allCounts.first { $0.name == source }?.count ?? 0
            return "\(moved) video\(moved == 1 ? "" : "s") move from “\(source)” into “\(target)”. “\(source)” disappears; no videos are deleted."
        case nil:
            return ""
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Categories")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(allCounts.count) categories · \(model.library.pinnedTags.count) pinned · \(model.library.count) videos")
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Find a category", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )

            Picker("Sort", selection: sortChoice) {
                ForEach(SortChoice.allCases, id: \.self) { choice in
                    Text(choice.label).tag(choice)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private func footerLabel() -> String {
        let shown = rows.count
        if shown == allCounts.count {
            return "Click a category to browse it. ⋯ pins, merges, renames or deletes."
        }
        return "\(shown) of \(allCounts.count) shown"
    }

    private var footer: some View {
        HStack {
            Text(footerLabel())
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }

    // MARK: - List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(allCounts.isEmpty ? "No categories yet" : "No category matches “\(query)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if allCounts.isEmpty {
                            Text("Categories appear as soon as you tag a video.")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }

                ForEach(rows) { tag in
                    row(tag)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ tag: TagCount) -> some View {
        let pinned = model.library.isPinned(tag.name)
        return HStack(spacing: 10) {
            Button {
                model.togglePin(tag.name)
            } label: {
                Image(systemName: pinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(pinned ? Theme.accent : Color.secondary.opacity(0.8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(pinned ? "Unpin from the sidebar" : "Pin to the top of the sidebar")

            Image(systemName: SymbolLibrary.category(tag.name))
                .font(.system(size: 12))
                .frame(width: 18)
                .foregroundStyle(.secondary)

            Button {
                model.select(.tag(tag.name))
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Text(tag.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("\(tag.count) video\(tag.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(pinned ? "Unpin from sidebar" : "Pin to sidebar") {
                    model.togglePin(tag.name)
                }
                Button("Browse \(tag.name)") {
                    model.select(.tag(tag.name))
                    dismiss()
                }
                Button("Present as slide deck") {
                    model.openDeckForTag(tag.name)
                    dismiss()
                }
                Divider()
                Button("Rename…") {
                    renameText = tag.name
                    dialog = .rename(tag.name)
                }
                Menu("Merge into…") {
                    let others = allCounts.filter { $0.name != tag.name }
                    if others.isEmpty {
                        Text("No other categories")
                    }
                    ForEach(others) { other in
                        Button("\(other.name)  ·  \(other.count)") {
                            dialog = .merge(tag.name, other.name)
                        }
                    }
                }
                Divider()
                Button("Delete from all videos", role: .destructive) {
                    dialog = .delete(tag.name)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering == tag.name ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 8)
        )
        .onHover { isHovering in
            hovering = isHovering ? tag.name : (hovering == tag.name ? nil : hovering)
        }
        .contextMenu {
            Button(pinned ? "Unpin from sidebar" : "Pin to sidebar") { model.togglePin(tag.name) }
            Button("Rename…") { renameText = tag.name; dialog = .rename(tag.name) }
            Button("Delete from all videos", role: .destructive) { dialog = .delete(tag.name) }
        }
    }
}


/// One control that expresses both the field and the direction.
enum SortChoice: String, CaseIterable, Hashable {
    case mostVideos
    case fewestVideos
    case nameAscending
    case nameDescending

    init(sort: CategorySort, ascending: Bool) {
        switch (sort, ascending) {
        case (.mostVideos, false): self = .mostVideos
        case (.mostVideos, true): self = .fewestVideos
        case (.name, true): self = .nameAscending
        case (.name, false): self = .nameDescending
        }
    }

    var sort: CategorySort {
        switch self {
        case .mostVideos, .fewestVideos: .mostVideos
        case .nameAscending, .nameDescending: .name
        }
    }

    var ascending: Bool {
        switch self {
        case .fewestVideos, .nameAscending: true
        case .mostVideos, .nameDescending: false
        }
    }

    var label: String {
        switch self {
        case .mostVideos: "Most videos"
        case .fewestVideos: "Fewest videos"
        case .nameAscending: "Name A–Z"
        case .nameDescending: "Name Z–A"
        }
    }
}
