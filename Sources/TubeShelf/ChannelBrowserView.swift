import SwiftUI
import AppKit
import TubeShelfCore

/// Channels are the second facet of a shelf that has grown up: after a few
/// hundred videos, "who made it" is often a better question than "what is it".
/// This browser answers it — sorted by how much you actually saved, with the
/// channel's usual category surfaced and a one-click deck.
struct ChannelBrowserView: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var hovering: String?

    private var allChannels: [TagCount] {
        model.library.channelCounts(
            sortedBy: model.categorySort,
            ascending: model.categorySortAscending
        )
    }

    private var rows: [TagCount] {
        let needle = SearchText.normalize(query)
        guard !needle.isEmpty else { return allChannels }
        return allChannels.filter { SearchText.matches(needle: needle, haystack: $0.name) }
    }

    private var totalVideos: Int {
        allChannels.reduce(0) { $0 + $1.count }
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Channels")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("\(allChannels.count) channels · \(totalVideos) videos")
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
                TextField("Find a channel", text: $query)
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

            Picker("Sort", selection: Binding(
                get: { SortChoice(sort: model.categorySort, ascending: model.categorySortAscending) },
                set: { choice in
                    model.categorySort = choice.sort
                    model.categorySortAscending = choice.ascending
                }
            )) {
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

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if rows.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(allChannels.isEmpty ? "No channels yet" : "No channel matches “\(query)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                }

                ForEach(rows) { channel in
                    row(channel)
                }
            }
            .padding(.vertical, 6)
        }
        .frame(maxHeight: .infinity)
    }

    private func row(_ channel: TagCount) -> some View {
        let affinity = model.library.channelAffinity(for: channel.name)
        return HStack(spacing: 10) {
            Monogram(name: channel.name, size: 26)

            Button {
                model.showChannel(channel.name)
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(channel.name)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if let affinity {
                            Text("usually \(affinity)")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("\(channel.count) video\(channel.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.openDeckForChannel(channel.name)
                dismiss()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .help("Present this channel as a deck")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering == channel.name ? Color.primary.opacity(0.05) : Color.clear)
                .padding(.horizontal, 8)
        )
        .onHover { inside in
            hovering = inside ? channel.name : (hovering == channel.name ? nil : hovering)
        }
        .contextMenu {
            Button("Show these videos") {
                model.showChannel(channel.name)
                dismiss()
            }
            Button("Present as slide deck") {
                model.openDeckForChannel(channel.name)
                dismiss()
            }
            Button("Copy channel name") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(channel.name, forType: .string)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(rows.count == allChannels.count
                 ? "Click a channel to filter the shelf. ▶ presents it."
                 : "\(rows.count) of \(allChannels.count) shown")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
    }
}

struct Monogram: View {
    let name: String
    var size: CGFloat = 26

    private var initials: String {
        let words = name
            .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
            .prefix(2)
        let letters = words.compactMap { $0.first }
        return letters.isEmpty ? String(name.prefix(1)).uppercased() : String(letters).uppercased()
    }

    /// Stable across launches: a channel should keep its colour.
    private var hue: Double {
        let total = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Double(total % 360)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                .fill(Color(hue: hue / 360.0, saturation: 0.45, brightness: 0.55))
            Text(initials)
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
