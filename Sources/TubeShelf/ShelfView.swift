import SwiftUI
import AppKit
import TubeShelfCore

struct ShelfView: View {
    let model: AppModel

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 244, maximum: 360), spacing: 18, alignment: .top)]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Image(systemName: SymbolLibrary.resolve(filterSymbolName))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text(model.filter.title)
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                }
                Text(model.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            ShelfSearchField(model: model)
            if !model.visibleVideos.isEmpty {
                Button {
                    if let first = model.pagedVideos.first ?? model.visibleVideos.first {
                        model.openDeck(startAt: first)
                    }
                } label: {
                    Label("Present", systemImage: "play.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [.command])
                .help("Walk through this category as slides")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var filterSymbolName: String {
        switch model.filter {
        case .all: "rectangle.stack"
        case .favorites: "star"
        case .unsorted: "tray"
        case .tag(let name): TagTaxonomy.symbol(for: name)
        case .channel: "person.2"
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.visibleVideos.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // A real anchor outside the grid so "scroll to top" does
                        // not consume a card cell.
                        Color.clear
                            .frame(height: 0)
                            .id("grid-top")

                        LazyVGrid(columns: columns, spacing: 18) {
                            ForEach(model.pagedVideos) { video in
                                VideoCard(video: video, model: model)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: model.pageWindow.pageIndex) { _, _ in
                    proxy.scrollTo("grid-top", anchor: .top)
                }
            }
            if model.showsPager {
                pager
            }
        }
    }

    private func emptyShelfMessage(_ elsewhere: (profile: Profile, count: Int)?) -> String {
        if let elsewhere {
            return "Nothing saved here yet. Add a link to start this shelf, switch to “\(elsewhere.profile.name)” (\(elsewhere.count)), or restore a backup into this profile."
        }
        return "Paste a YouTube link and TubeShelf fetches the title, thumbnail and suggested categories. Everything stays on this Mac."
    }

    private var pager: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)
            HStack(spacing: 12) {
                Button {
                    model.previousPage()
                } label: {
                    Label("Previous", systemImage: "chevron.left")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.pageWindow.isFirst)
                .keyboardShortcut(.leftArrow, modifiers: [.option])

                Spacer(minLength: 8)

                Text(model.pageWindow.rangeLabel)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)

                Menu {
                    ForEach(0..<model.pageWindow.pageCount, id: \.self) { index in
                        Button {
                            model.goToPage(index)
                        } label: {
                            if index == model.pageWindow.pageIndex {
                                Label("Page \(index + 1)", systemImage: "checkmark")
                            } else {
                                Text("Page \(index + 1)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(model.pageWindow.pageLabel)
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Jump to a page")

                Spacer(minLength: 8)

                Button {
                    model.nextPage()
                } label: {
                    Label("Next", systemImage: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(model.pageWindow.isLast)
                .keyboardShortcut(.rightArrow, modifiers: [.option])
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(.bar)
        }
    }

    private var emptyState: some View {
        Group {
            if model.isSearching {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "Nothing matches “\(model.query)”",
                    message: model.searchScope == .titles
                        ? "Only video titles were searched. Switch the scope to Everything to include channels, notes and categories."
                        : "Search covers titles, channels, notes and categories. Try a shorter word, or clear the search.",
                    primaryTitle: "Clear search",
                    primaryAction: { model.query = "" },
                    secondaryTitle: model.searchScope == .titles ? "Search everything" : nil,
                    secondaryAction: model.searchScope == .titles ? { model.searchScope = .everything } : nil
                )
            } else if model.library.isEmpty {
                let elsewhere = model.otherPopulatedProfiles.first
                EmptyStateView(
                    symbol: elsewhere == nil ? "square.stack.3d.up" : "person.crop.circle.badge.questionmark",
                    title: elsewhere == nil
                        ? "Your shelf is empty"
                        : "“\(model.currentProfile?.name ?? "This profile")” is empty",
                    message: emptyShelfMessage(elsewhere),
                    primaryTitle: elsewhere.map { "Switch to \($0.profile.name) · \($0.count) video\($0.count == 1 ? "" : "s")" } ?? "Add a YouTube link",
                    primaryAction: {
                        if let elsewhere {
                            model.switchProfile(elsewhere.profile.id)
                        } else {
                            model.isAddPresented = true
                        }
                    },
                    secondaryTitle: "Add a YouTube link",
                    secondaryAction: {
                        // Starting fresh in an empty profile is a first-class action,
                        // not something hidden behind the toolbar.
                        model.isAddPresented = true
                    },
                    tertiaryTitle: "Restore from backup…",
                    tertiaryAction: {
                        BackupActions.restore(model)
                    }
                )
            } else if case .favorites = model.filter {
                EmptyStateView(
                    symbol: "star",
                    title: "No favorites yet",
                    message: "Right-click a video on the shelf and choose “Mark as favorite” to pin the ones you keep coming back to."
                )
            } else if case .channel(let name) = model.filter {
                EmptyStateView(
                    symbol: "person.2",
                    title: "Nothing from \(name)",
                    message: "This channel no longer has saved videos. Browse everything else, or add a link from this channel.",
                    primaryTitle: "Show all videos",
                    primaryAction: { model.select(.all) }
                )
            } else if case .unsorted = model.filter {
                EmptyStateView(
                    symbol: "tray",
                    title: "Everything is filed",
                    message: "Every saved video has at least one category."
                )
            } else {
                EmptyStateView(
                    symbol: "tag",
                    title: "Nothing in this category",
                    message: "Videos you file here will show up as a shelf, and as a deck you can present.",
                    primaryTitle: "Add a video",
                    primaryAction: { model.isAddPresented = true }
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VideoCard: View {
    let video: Video
    let model: AppModel

    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                ThumbnailView(videoID: video.youtubeID)
                    .overlay {
                        ZStack {
                            if hovering {
                                Circle()
                                    .fill(.black.opacity(0.55))
                                    .frame(width: 46, height: 46)
                                Image(systemName: "play.fill")
                                    .font(.system(size: 17, weight: .bold))
                                    .foregroundStyle(.white)
                                    .offset(x: 1)
                            }
                        }
                        .animation(.easeOut(duration: 0.15), value: hovering)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !video.durationLabel.isEmpty {
                            Text(video.durationLabel)
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 4))
                                .foregroundStyle(.white)
                                .padding(7)
                        }
                    }

                if video.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(7)
                }
            }

            Text(video.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 5) {
                Text(video.channel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(video.addedLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            if video.tags.isEmpty {
                Text("Unsorted")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            } else {
                TagChipRow(tags: video.tags, limit: 2) { tag in
                    model.query = ""
                    model.select(.tag(tag))
                }
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Theme.surface(scheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .strokeBorder(Theme.hairline(scheme), lineWidth: 1)
        )
        .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
        .scaleEffect(hovering ? 1.012 : 1)
        .animation(.easeOut(duration: 0.16), value: hovering)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onTapGesture { model.openDeck(startAt: video) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open slide deck") { model.openDeck(startAt: video) }
            Button("Open on YouTube") { NSWorkspace.shared.open(video.watchURL) }
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(video.watchURL.absoluteString, forType: .string)
                model.flash("Link copied")
            }
            Divider()
            Button(video.isFavorite ? "Remove from favorites" : "Mark as favorite") {
                model.toggleFavorite(video)
            }
            Button("More from \(video.channel)") {
                model.showChannel(video.channel)
            }
            Button("Edit categories and note…") { model.editingVideoID = video.id }
            Divider()
            Button("Remove from shelf", role: .destructive) { model.delete(video) }
        }
    }
}


struct ShelfSearchField: View {
    let model: AppModel

    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(focused ? Theme.accent : Color.secondary)

            TextField(placeholder, text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($focused)
                .onSubmit { focused = false }

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }

            Divider().frame(height: 13)

            Menu {
                Picker("Search scope", selection: $model.searchScope) {
                    ForEach(SearchScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.searchScope.label)
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Titles only, or everything including channel, note and category")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    focused ? Theme.accent.opacity(0.55) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
        )
        .onChange(of: model.searchFocusRequest) { _, _ in
            focused = true
        }
    }

    private var placeholder: String {
        model.searchScope == .titles ? "Search video titles" : "Search everything"
    }
}
