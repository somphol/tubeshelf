import SwiftUI
import AppKit
import TubeShelfCore

@main
struct TubeShelfApp: App {
    @State private var model = AppModel(profileStore: AppModel.defaultProfileStore())

    var body: some Scene {
        WindowGroup("TubeShelf") {
            RootView(model: model)
                .frame(minWidth: 940, idealWidth: 1240, minHeight: 620, idealHeight: 800)
        }
        .defaultSize(width: 1240, height: 800)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Add Video…") {
                    model.isAddPresented = true
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Add Videos from Playlist…") {
                    model.openPlaylistImport()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Add Playlist to Catalog…") {
                    model.isAddPlaylistToCatalogPresented = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift, .option])

                Button("Open Playlist Catalog…") {
                    model.browsePlaylistCatalog()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button("Tidy Categories…") {
                    model.isTidyPresented = true
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button("Manage Categories…") {
                    model.openCategoryManager()
                }
                .keyboardShortcut("k", modifiers: .command)

                Button("Browse Channels…") {
                    model.openChannelBrowser()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])

                Button("Shuffle") {
                    model.shuffleCurrent()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(model.isBrowsingPlaylists
                          ? model.visiblePlaylists.isEmpty
                          : model.visibleVideos.isEmpty)

                Button("Select Videos") {
                    if model.isSelecting {
                        model.exitSelection()
                    } else {
                        model.isSelecting = true
                    }
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.isBrowsingPlaylists)

                Button("Search Videos") {
                    model.focusSearch()
                }
                .keyboardShortcut("f", modifiers: .command)

                Divider()
                Button("Back up Shelf…") {
                    BackupActions.backUp(model)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Button("Back up to Google Drive") {
                    BackupActions.backUpToDrive(model)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift, .option])

                Button("Restore from Backup…") {
                    BackupActions.restore(model)
                }

                Divider()
                Button("Present Current Category") {
                    if let first = model.visibleVideos.first {
                        model.openDeck(startAt: first)
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.visibleVideos.isEmpty)

                Button("Back to Shelf") {
                    model.closeDeck()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(model.deck == nil)
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

struct SettingsView: View {
    let model: AppModel
    @State private var confirmReset = false

    @ViewBuilder
    private var driveStatusLine: some View {
        switch model.driveStatus {
        case .ready(let account):
            Text("Google Drive · \(account) → TubeShelf Backups")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        case .notFound:
            HStack(spacing: 6) {
                Text("Google Drive for Desktop not found.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Button("Install it…") {
                    if let url = URL(string: "https://www.google.com/drive/download/") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 10.5))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                LogoMark(size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TubeShelf")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("A local shelf for the YouTube videos you want to find again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Tag suggestions", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.modelStatus.isAvailable ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(model.modelStatus.shortLabel)
                        .font(.system(size: 11.5, weight: .medium))
                }
                Text(model.modelStatus.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
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

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Label("Browsing", systemImage: "rectangle.grid.2x2")
                    .font(.system(size: 12, weight: .semibold))
                HStack {
                    Text("Videos per page")
                        .font(.system(size: 11.5))
                    Spacer()
                    Picker("Videos per page", selection: Binding(
                        get: { model.pageSize },
                        set: { model.pageSize = $0 }
                    )) {
                        ForEach(Preferences.pageSizeOptions, id: \.self) { size in
                            Text("\(size)").tag(size)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 90)
                }
                Text("Large categories are split into pages so the grid stays quick. The deck still runs through every video in the category.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle("Index in Spotlight", isOn: Binding(
                    get: { model.spotlightEnabled },
                    set: { model.spotlightEnabled = $0 }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 11.5))

                Text("Titles, channels, categories and courses appear in ⌘Space. Turning this off removes them.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Label("Library", systemImage: "externaldrive")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(model.library.count) videos · \(model.library.tagCounts.count) categories")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                Text(model.store.fileURL.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack(spacing: 10) {
                    Button("Back up…") { BackupActions.backUp(model) }
                        .controlSize(.small)
                    Button("Back up to Drive") { BackupActions.backUpToDrive(model) }
                        .controlSize(.small)
                        .disabled(model.driveStatus == .notFound)
                        .help(model.driveStatus == .notFound
                              ? "Install Google Drive for Desktop to enable this"
                              : "Writes into My Drive → TubeShelf Backups")
                    Button("Restore…") { BackupActions.restore(model) }
                        .controlSize(.small)
                    Button("Reveal library file") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.store.fileURL])
                    }
                    .controlSize(.small)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button("Remove all videos…") { confirmReset = true }
                        .controlSize(.small)
                        .disabled(model.library.isEmpty)
                    Spacer(minLength: 0)
                }
                driveStatusLine
                Text("A backup is one JSON file: videos, categories, notes and pins. Thumbnails are re-downloaded, so the file stays small enough for Drive.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 460, height: 560)
        .alert("Remove all \(model.library.count) videos?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) {
                for video in model.library.videos { model.delete(video) }
            }
        } message: {
            Text("The library file is rewritten empty. Nothing is deleted from YouTube.")
        }
    }
}
