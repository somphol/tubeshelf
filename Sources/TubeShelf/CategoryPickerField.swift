import SwiftUI
import TubeShelfCore

/// Adds categories to a video from three sources at once:
///   1. your existing categories (with counts),
///   2. the built-in library,
///   3. a brand-new name typed here.
///
/// With an empty field it offers your unused categories as one-tap chips. As soon
/// as you type, those collapse into a match list: "Create …" first, then every
/// existing category that matches, then library categories.
struct CategoryPickerField: View {
    let model: AppModel
    var applied: [String]
    var placeholder: String = "Type a new category, or pick one…"
    var autoFocus: Bool = false
    var onAdd: (String) -> Void

    @State private var text = ""
    @State private var hovering: String?
    @FocusState private var focused: Bool

    private enum Kind: Equatable {
        case create
        case existing(Int)
        case library
        case alreadyAdded
    }

    private struct Suggestion: Identifiable, Equatable {
        let name: String
        let kind: Kind
        var id: String {
            switch kind {
            case .create: "create-\(name)"
            case .existing: "existing-\(name)"
            case .library: "library-\(name)"
            case .alreadyAdded: "added-\(name)"
            }
        }
    }

    // MARK: - Data

    private var appliedKeys: Set<String> {
        Set(applied.map { $0.lowercased() })
    }

    private var existing: [TagCount] {
        model.library.tagCounts
    }

    private var availableExisting: [TagCount] {
        existing.filter { !appliedKeys.contains($0.name.lowercased()) }
    }

    private var matchingExisting: [TagCount] {
        let needle = SearchText.normalize(text)
        guard !needle.isEmpty else { return [] }
        return availableExisting.filter {
            SearchText.matches(needle: needle, haystack: $0.name)
        }
    }

    private var matchingLibrary: [String] {
        let needle = SearchText.normalize(text)
        guard !needle.isEmpty else { return [] }
        return TagTaxonomy.names.filter { name in
            !appliedKeys.contains(name.lowercased())
                && !existing.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                && SearchText.matches(needle: needle, haystack: name)
        }
    }

    private var newCategoryName: String? {
        guard let cleaned = TagNormalizer.canonical(text) else { return nil }
        let key = cleaned.lowercased()
        guard !appliedKeys.contains(key) else { return nil }
        guard !existing.contains(where: { $0.name.lowercased() == key }) else { return nil }
        guard !TagTaxonomy.names.contains(where: { $0.lowercased() == key }) else { return nil }
        return cleaned
    }

    private var alreadyAppliedMatch: String? {
        guard let cleaned = TagNormalizer.canonical(text) else { return nil }
        return applied.first { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
    }

    private var quickAdds: [TagCount] {
        Array(availableExisting.prefix(7))
    }

    private var suggestions: [Suggestion] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var items: [Suggestion] = []
        if let alreadyAppliedMatch {
            items.append(Suggestion(name: alreadyAppliedMatch, kind: .alreadyAdded))
        }
        if let newCategoryName {
            items.append(Suggestion(name: newCategoryName, kind: .create))
        }
        items.append(contentsOf: matchingExisting.prefix(4).map {
            Suggestion(name: $0.name, kind: .existing($0.count))
        })
        items.append(contentsOf: matchingLibrary.prefix(3).map {
            Suggestion(name: $0, kind: .library)
        })
        return items
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            field

            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !suggestions.isEmpty {
                    suggestionList
                } else {
                    Text("Type a name to create it, or browse with the arrow.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(quickAdds.isEmpty ? "No categories yet" : "Your categories")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                        Button {
                            focused = true
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .bold))
                                Text("New category")
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                        }
                        .buttonStyle(.link)
                        .help("Type a name in the field, then press Return")
                        Spacer(minLength: 0)
                    }

                    if quickAdds.isEmpty {
                        Text("Type a name above and press ⏎ to start your first category. It becomes available on every video.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        FlowWrap(items: quickAdds) { category in
                            quickAddChip(category)
                        }
                    }
                }
            }
        }
        .onAppear {
            if autoFocus { focused = true }
        }
        #if DEBUG
        .onAppear {
            if text.isEmpty, let prefill = SnapshotConfig.pickerPrefill {
                text = prefill
            }
        }
        #endif
    }

    private var field: some View {
        HStack(spacing: 7) {
            HStack(spacing: 6) {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($focused)
                    .onSubmit(submit)

                if text.isEmpty {
                    Text("⏎")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                        .help("Type a name, then press Return to create the category")
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        focused ? Theme.accent.opacity(0.45) : Color.clear,
                        lineWidth: 1
                    )
            )

            Menu {
                if !availableExisting.isEmpty {
                    Section("Your categories") {
                        ForEach(availableExisting) { category in
                            Button {
                                add(category.name)
                            } label: {
                                Label(
                                    "\(category.name)  ·  \(category.count)",
                                    systemImage: SymbolLibrary.category(category.name)
                                )
                            }
                        }
                    }
                }
                Section("Add from library") {
                    ForEach(TagTaxonomy.names.filter { name in
                        !appliedKeys.contains(name.lowercased())
                            && !existing.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                    }, id: \.self) { name in
                        Button {
                            add(name)
                        } label: {
                            Label(name, systemImage: SymbolLibrary.category(name))
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("Browse every category")
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(suggestions) { suggestion in
                suggestionRow(suggestion)
            }
        }
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 6, y: 2)
    }

    private func suggestionRow(_ suggestion: Suggestion) -> some View {
        let isHovered = hovering == suggestion.id
        let disabled = suggestion.kind == .alreadyAdded

        return Button {
            switch suggestion.kind {
            case .alreadyAdded: break
            case .create, .existing, .library: add(suggestion.name)
            }
        } label: {
            HStack(spacing: 8) {
                icon(for: suggestion)
                    .frame(width: 16)
                Text(label(for: suggestion))
                    .font(.system(size: 12, weight: suggestion.kind == .create ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let detail = detail(for: suggestion) {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered && !disabled ? Color.primary.opacity(0.06) : Color.clear)
                    .padding(.horizontal, 3)
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .onHover { inside in
            hovering = inside ? suggestion.id : (hovering == suggestion.id ? nil : hovering)
        }
    }

    @ViewBuilder
    private func icon(for suggestion: Suggestion) -> some View {
        switch suggestion.kind {
        case .create:
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        case .existing:
            Image(systemName: SymbolLibrary.category(suggestion.name))
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent.opacity(0.85))
        case .library:
            Image(systemName: SymbolLibrary.category(suggestion.name))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .alreadyAdded:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func label(for suggestion: Suggestion) -> String {
        switch suggestion.kind {
        case .create: "Create “\(suggestion.name)”"
        default: suggestion.name
        }
    }

    private func detail(for suggestion: Suggestion) -> String? {
        switch suggestion.kind {
        case .create: "Press ⏎ to create"
        case .existing(let count): "\(count) video\(count == 1 ? "" : "s")"
        case .library: "Library"
        case .alreadyAdded: "Already added"
        }
    }

    private func quickAddChip(_ category: TagCount) -> some View {
        Button {
            add(category.name)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 8.5, weight: .bold))
                Text(category.name)
                    .font(.system(size: 10.5, weight: .medium))
                    .lineLimit(1)
                Text("\(category.count)")
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Add \(category.name)")
    }

    private func submit() {
        guard let cleaned = TagNormalizer.canonical(text) else { return }
        let match = existing.first { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }
        add(match?.name ?? cleaned)
    }

    private func add(_ name: String) {
        guard let cleaned = TagNormalizer.canonical(name) else { return }
        onAdd(cleaned)
        text = ""
    }
}
