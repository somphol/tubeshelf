import SwiftUI
import TubeShelfCore

struct RootView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model

        ZStack {
            NavigationSplitView {
                SidebarView(model: model)
                    .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
            } detail: {
                ShelfView(model: model)
            }
            .toolbar(model.deck == nil ? .visible : .hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.openChannelBrowser()
                    } label: {
                        Label("Channels", systemImage: "person.2")
                    }
                    .help("Browse channels (⇧⌘K)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Add Videos from Playlist…") { model.openPlaylistImport() }
                        Button("Add Playlist to Catalog…") { model.isAddPlaylistToCatalogPresented = true }
                        Divider()
                        Button("Open Playlist Catalog…") { model.browsePlaylistCatalog() }
                    } label: {
                        Label("Playlists", systemImage: "list.bullet.rectangle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Playlist videos, or keep a playlist as a course (⇧⌘N)")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isAddPresented = true
                    } label: {
                        Label("Add video", systemImage: "plus")
                    }
                    .help("Save a YouTube link (⌘N)")
                }
            }

            if model.deck != nil {
                DeckView(model: model)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
                    .zIndex(2)
            }
        }
        .animation(.spring(duration: 0.32), value: model.deck != nil)
        .sheet(isPresented: $model.isAddPresented) {
            AddVideoSheet(model: model)
        }
        .sheet(isPresented: $model.isCategoryManagerPresented) {
            CategoryManagerView(model: model)
        }
        .sheet(isPresented: $model.isChannelBrowserPresented) {
            ChannelBrowserView(model: model)
        }
        .sheet(isPresented: $model.isProfileManagerPresented) {
            ProfileManagerView(model: model)
        }
        .sheet(isPresented: $model.isPlaylistImportPresented) {
            PlaylistImportSheet(model: model)
        }
        .sheet(isPresented: $model.isPlaylistCatalogPresented) {
            PlaylistCatalogView(model: model)
        }
        .sheet(isPresented: $model.isAddPlaylistToCatalogPresented) {
            AddPlaylistToCatalogSheet(model: model)
        }
        .sheet(isPresented: Binding(
            get: { model.editingVideoID != nil },
            set: { if !$0 { model.editingVideoID = nil } }
        )) {
            if let video = model.editingVideo {
                TagEditorSheet(model: model, video: video)
            }
        }
        .overlay(alignment: .bottom) {
            ToastView(message: model.toast)
                .padding(.bottom, 22)
        }
        .onChange(of: model.filter) { _, _ in model.refreshDeck() }
        #if DEBUG
        .task { Snapshotter.runIfRequested(model: model) }
        #endif
    }
}

struct SidebarView: View {
    let model: AppModel
    @State private var showModelInfo = false
    @State private var renameText = ""
    @State private var dialog: CategoryDialog?

    private enum CategoryDialog: Identifiable {
        case rename(String)
        case delete(String)
        case merge(source: String, target: String)

        var id: String {
            switch self {
            case .rename(let name): "rename-\(name)"
            case .delete(let name): "delete-\(name)"
            case .merge(let source, let target): "merge-\(source)-\(target)"
            }
        }
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            HStack(spacing: 9) {
                LogoMark(size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text("TubeShelf")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    profileSwitcher
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Filter categories & channels", text: $model.sidebarQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !model.sidebarQuery.isEmpty {
                    Button {
                        model.sidebarQuery = ""
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
                    .fill(Color.primary.opacity(0.06))
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            List(selection: Binding(
                // A channel filter has no sidebar row; returning nil keeps the
                // list from falsely highlighting "All videos".
                get: { model.filter },
                set: { if let value = $0 { model.select(value) } }
            )) {
                Section("Library") {
                    row(.all, symbol: "rectangle.stack", title: "All videos", count: model.library.count)
                    row(.favorites, symbol: "star", title: "Favorites", count: model.library.favoritesCount)
                    row(.unwatched, symbol: "eye.slash", title: "Unwatched", count: model.library.unwatchedCount)
                    row(.playlists, symbol: "list.bullet.rectangle", title: "Playlist Catalog", count: model.playlists.count)
                    row(.unsorted, symbol: "tray", title: "Unsorted", count: model.library.unsortedCount)
                }

                if model.hasPinnedCategories {
                    Section {
                        ForEach(model.pinnedTagCounts) { tag in
                            categoryRow(tag, isPinned: true)
                        }
                    } header: {
                        HStack(spacing: 5) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Pinned")
                            Spacer(minLength: 0)
                        }
                    }
                }

                if !model.sidebarChannels.isEmpty {
                    Section {
                        ForEach(model.sidebarChannels) { channel in
                            ChannelSidebarRow(
                                name: channel.name,
                                count: channel.count,
                                isSelected: model.filter == .channel(channel.name),
                                onPresent: { model.openDeckForChannel(channel.name) }
                            )
                            .contextMenu {
                                Button("Show these videos") { model.showChannel(channel.name) }
                                Button("Present as slide deck") { model.openDeckForChannel(channel.name) }
                                Divider()
                                Button("Browse all channels…") { model.openChannelBrowser() }
                                Button("Copy channel name") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(channel.name, forType: .string)
                                }
                            }
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Text("Channels")
                            Spacer(minLength: 0)
                            Button {
                                model.openChannelBrowser()
                            } label: {
                                HStack(spacing: 2) {
                                    Text("All \(model.channelTotal)")
                                        .font(.system(size: 9.5, weight: .medium))
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 7, weight: .bold))
                                }
                            }
                            .buttonStyle(.link)
                            .help("Browse all channels (⇧⌘K)")
                        }
                    }
                }

                Section {
                    if model.unpinnedTagCounts.isEmpty {
                        Text(categoryEmptyLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.vertical, 2)
                    }
                    ForEach(model.unpinnedTagCounts) { tag in
                        categoryRow(tag, isPinned: false)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Text("Categories")
                        Spacer(minLength: 0)
                        Menu {
                            Picker("Sort by", selection: $model.categorySort) {
                                ForEach(CategorySort.allCases, id: \.self) { sort in
                                    Text(sort.label).tag(sort)
                                }
                            }
                            Divider()
                            Toggle("Ascending", isOn: $model.categorySortAscending)
                            Divider()
                            Button("Manage categories…") { model.openCategoryManager() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .contentShape(Rectangle())
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 16)
                        .help("Sort or manage categories")
                    }
                }
            }
            .listStyle(.sidebar)

            Divider().opacity(0.5)

            Button {
                showModelInfo.toggle()
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.modelStatus.isAvailable ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(model.modelStatus.shortLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showModelInfo, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tag suggestions")
                        .font(.headline)
                    Text(model.modelStatus.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Nothing you save is sent to a server. YouTube metadata is fetched directly from YouTube.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    if !model.modelStatus.isAvailable {
                        Button("Open Apple Intelligence settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Apple-Intelligence-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                }
                .padding(14)
                .frame(width: 300)
            }
        }
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

    private var profileSwitcher: some View {
        Menu {
            Section("Profiles") {
                ForEach(model.profiles) { profile in
                    Button {
                        model.switchProfile(profile.id)
                    } label: {
                        if profile.id == model.activeProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
            Divider()
            Button("Add from Backup…") { BackupActions.importProfile(model) }
            Button("New Empty Profile…") { BackupActions.promptForNewProfile(model) }
            Button("Manage Profiles…") { model.isProfileManagerPresented = true }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 9, weight: .medium))
                Text(model.currentProfile?.name ?? "Profile")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 6, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Switch profile — each shelf is a separate folder")
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
        case .delete(let name):
            "“\(name)” is removed from every video. The videos themselves stay on the shelf."
        case .merge(let source, let target):
            "\(mergeCount(source)) video\(mergeCount(source) == 1 ? "" : "s") move from “\(source)” into “\(target)”. “\(source)” disappears; no videos are deleted."
        default:
            "Every video filed under this category moves with it."
        }
    }

    private func mergeCount(_ name: String) -> Int {
        model.library.tagCounts.first { $0.name == name }?.count ?? 0
    }

    private var categoryEmptyLabel: String {
        if !model.sidebarQuery.isEmpty { return "No match" }
        if model.hasPinnedCategories { return "All categories are pinned" }
        return "No categories yet"
    }

    private func categoryRow(_ tag: TagCount, isPinned: Bool) -> some View {
        CategoryRow(
            title: tag.name,
            symbol: SymbolLibrary.category(tag.name),
            count: tag.count,
            isSelected: model.filter == .tag(tag.name),
            isPinned: isPinned,
            onPresent: { model.openDeckForTag(tag.name) }
        )
        .contextMenu {
            Button(isPinned ? "Unpin category" : "Pin category") {
                model.togglePin(tag.name)
            }
            Button("Present this category") {
                model.openDeckForTag(tag.name)
            }
            Divider()
            Button("Rename category…") {
                renameText = tag.name
                dialog = .rename(tag.name)
            }
            Menu("Merge into…") {
                let others = model.library.tagCounts.filter {
                    $0.name.caseInsensitiveCompare(tag.name) != .orderedSame
                }
                if others.isEmpty {
                    Text("No other categories")
                }
                ForEach(others) { other in
                    Button("\(other.name)  ·  \(other.count)") {
                        dialog = .merge(source: tag.name, target: other.name)
                    }
                }
            }
            Button("Manage categories…") { model.openCategoryManager() }
            Divider()
            Button("Delete category from all videos", role: .destructive) {
                dialog = .delete(tag.name)
            }
        }
    }

    private func row(_ filter: ShelfFilter, symbol: String, title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: SymbolLibrary.resolve(symbol))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 17)
                .foregroundStyle(model.filter == filter ? Theme.accent : Color.secondary)
            Text(title)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .tag(filter)
    }
}

struct ChannelSidebarRow: View {
    let name: String
    let count: Int
    let isSelected: Bool
    let onPresent: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 7) {
            Monogram(name: name, size: 17)
            Text(name)
                .font(.system(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 4)
            if hovering {
                Button(action: onPresent) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Present \(name) as a slide deck")
            } else {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .help(name)
        .tag(ShelfFilter.channel(name))
    }
}

struct CategoryRow: View {
    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    var isPinned: Bool = false
    let onPresent: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SymbolLibrary.resolve(symbol))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 17)
                .foregroundStyle(isSelected ? Theme.accent : Color.secondary)
            Text(title)
                .font(.system(size: 12.5))
                .lineLimit(1)
            if isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
            Spacer(minLength: 4)
            if hovering {
                Button(action: onPresent) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Present \(title) as a slide deck")
            } else {
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .onHover { hovering = $0 }
        .help(title)
        .tag(ShelfFilter.tag(title))
    }
}

struct LogoMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.02)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.accent.opacity(0.25), radius: 4, y: 1)
    }
}

struct ToastView: View {
    let message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(message)
        }
    }
}
