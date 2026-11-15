import SwiftUI
import TubeShelfCore

/// Filterable list of categories present in the selection, for removing them in
/// bulk. Mirrors the normal editors: search first, counts visible, sorted.
struct BulkRemoveCategorySheet: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = Set<String>()
    @State private var sort: CategorySort = .mostVideos

    private var counts: [TagCount] {
        var tally: [String: Int] = [:]
        var spelling: [String: String] = [:]
        for video in model.selectedVideos {
            for tag in video.tags {
                let key = tag.lowercased()
                tally[key, default: 0] += 1
                spelling[key] = spelling[key] ?? tag
            }
        }
        let items = tally.map { TagCount(name: spelling[$0.key] ?? $0.key, count: $0.value) }
        switch sort {
        case .mostVideos:
            return items.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        case .name:
            return items.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var rows: [TagCount] {
        let needle = SearchText.normalize(query)
        guard !needle.isEmpty else { return counts }
        return counts.filter { SearchText.matches(needle: needle, haystack: $0.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Remove categories")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("From \(model.selectedCount) selected video\(model.selectedCount == 1 ? "" : "s").")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(20)

            Divider().opacity(0.4)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Filter categories", text: $query)
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
                Picker("Sort", selection: $sort) {
                    Text("Most used").tag(CategorySort.mostVideos)
                    Text("Name").tag(CategorySort.name)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 110)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(20)

            ScrollView {
                LazyVStack(spacing: 0) {
                    if rows.isEmpty {
                        Text(counts.isEmpty ? "No categories in this selection" : "No match")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 24)
                    }
                    ForEach(rows) { tag in
                        let isOn = selected.contains(tag.name)
                        Button {
                            if isOn { selected.remove(tag.name) } else { selected.insert(tag.name) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isOn ? Theme.accent : Color.secondary.opacity(0.6))
                                Text(tag.name)
                                    .font(.system(size: 12))
                                Spacer()
                                Text("\(tag.count)")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 260)

            Divider().opacity(0.4)

            HStack {
                Text(selected.isEmpty ? "Nothing selected" : "\(selected.count) selected")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Remove") {
                    for tag in selected { model.bulkRemoveTag(tag) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
