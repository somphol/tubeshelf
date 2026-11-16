import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TubeShelfCore

/// File panels, name prompts and the restore confirmation live here so the
/// Settings window, the sidebar menu and the menu bar run the same code.
@MainActor
enum BackupActions {
    // MARK: - Backup / restore the active shelf

    static func backUp(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.title = "Back up \(model.currentProfile?.name ?? "your shelf")"
        panel.prompt = "Back up"
        panel.nameFieldStringValue = ShelfBackup.suggestedFileName(
            profileName: model.currentProfile?.name
        )
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.backup(to: url)
        } catch {
            model.flash("Backup failed: \(error.localizedDescription)")
        }
    }

    static func restore(_ model: AppModel) {
        let panel = NSOpenPanel()
        panel.title = "Restore into \(model.currentProfile?.name ?? "this shelf")"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let contents: (library: Library, playlists: [PlaylistRecord])
        do {
            contents = try BackupService().readContents(from: url)
        } catch {
            model.flash("Restore failed: \(error.localizedDescription)")
            return
        }

        let incoming = ShelfSnapshot(library: contents.library, playlists: contents.playlists)
        let name = url.lastPathComponent
        let mine = model.snapshot

        // A backup with no videos must never silently delete a populated
        // profile through a merge. Replacing is still available, with its own
        // warning.
        if incoming.library.videos.isEmpty,
           !mine.library.videos.isEmpty {
            presentEmptyBackupWarning(model, incoming: incoming, name: name)
            return
        }

        let base = model.mergeBase
        if let base, mine == base {
            presentReplace(
                model,
                incoming: incoming,
                name: name,
                note: "There are no local edits since the last backup, so this replaces the profile."
            )
            return
        }

        // With no common ancestor, the merge keeps every current video and
        // course, adds incoming-only items, and asks only where an existing
        // field differs. It never treats a missing video as a deletion.
        let result = ShelfMerger.merge(base: base, mine: mine, theirs: incoming)
        let newBase: ShelfSnapshot? = base == nil ? incoming : nil
        if result.stats.changes == 0, result.conflicts.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Already up to date"
            alert.informativeText = "That backup has nothing this profile does not already have."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        if result.conflicts.isEmpty {
            presentMergeChoice(model, incoming: incoming, result: result, name: name, newBase: newBase)
        } else {
            model.mergeReview = MergeReviewState(
                result: result,
                incoming: incoming,
                name: name,
                newBase: newBase
            )
        }
    }

    private static func presentReplace(
        _ model: AppModel,
        incoming: ShelfSnapshot,
        name: String,
        note: String
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Replace this profile with the backup?"
        alert.informativeText = """
        “\(name)” has \(incoming.library.count) video\(incoming.library.count == 1 ? "" : "s") and \(incoming.playlists.count) playlist\(incoming.playlists.count == 1 ? "" : "s").
        This profile (“\(model.currentProfile?.name ?? "shelf")”) has \(model.library.count) videos and \(model.playlists.count) playlists.
        \(note)
        Full backups of the current shelf and the replaced shelf are saved in Application Support, and the current library and catalog are copied aside too.
        """
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.replace(with: incoming, name: name)
    }

    private static func presentMergeChoice(
        _ model: AppModel,
        incoming: ShelfSnapshot,
        result: ShelfMergeResult,
        name: String,
        newBase: ShelfSnapshot?
    ) {
        let alert = NSAlert()
        alert.messageText = "Merge \(result.stats.changes) backup change\(result.stats.changes == 1 ? "" : "s")?"
        alert.informativeText = """
        “\(name)” has \(incoming.library.count) video\(incoming.library.count == 1 ? "" : "s") and \(incoming.playlists.count) playlist\(incoming.playlists.count == 1 ? "" : "s").
        \(mergeStatsLine(result.stats))
        The current profile stays; the backup is merged into it. Full backups are saved before and after the merge, and you can undo it.
        """
        alert.addButton(withTitle: "Merge")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            model.applyMerge(result.snapshot, name: name, newBase: newBase)
        case .alertSecondButtonReturn:
            model.replace(with: incoming, name: name)
        default:
            break
        }
    }

    private static func presentEmptyBackupWarning(
        _ model: AppModel,
        incoming: ShelfSnapshot,
        name: String
    ) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "That backup has no videos"
        alert.informativeText = """
        “\(name)” has no videos\(incoming.playlists.isEmpty ? " and no playlists" : ""). Merging could remove this profile's videos.
        Replace the profile instead? A backup is saved before and after.
        """
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.replace(with: incoming, name: name)
    }

    private static func mergeStatsLine(_ stats: MergeStats) -> String {
        var parts: [String] = []
        if stats.added > 0 { parts.append("\(stats.added) added") }
        if stats.updated > 0 { parts.append("\(stats.updated) updated") }
        if stats.deleted > 0 { parts.append("\(stats.deleted) removed") }
        if stats.kept > 0 { parts.append("\(stats.kept) kept locally") }
        return parts.isEmpty ? "No field changes." : parts.joined(separator: "  ·  ")
    }

    // MARK: - Google Drive

    /// Writes into the mounted Google Drive folder. No OAuth, no upload: Drive for
    /// Desktop syncs the file like any other file.
    static func backUpToDrive(_ model: AppModel) {
        let drives = model.cloudLocator.googleDrives()
        guard !drives.isEmpty else {
            presentNoDrive(model)
            return
        }

        guard let drive = chooseDrive(drives, model: model) else { return }

        do {
            let folder = try model.cloudLocator.backupFolder(in: drive)
            let url = folder.appendingPathComponent(
                ShelfBackup.suggestedFileName(profileName: model.currentProfile?.name)
            )
            try model.backup(to: url)
            Preferences.driveAccountPath = drive.myDrive.path
            model.flash("Backed up to Google Drive · \(drive.accountName)")
        } catch {
            model.flash("Drive backup failed: \(error.localizedDescription)")
        }
    }

    private static func chooseDrive(_ drives: [CloudDrive], model: AppModel) -> CloudDrive? {
        if drives.count == 1 { return drives[0] }
        if let remembered = Preferences.driveAccountPath,
           let match = drives.first(where: { $0.myDrive.path == remembered }) {
            return match
        }

        let alert = NSAlert()
        alert.messageText = "Which Google Drive account?"
        alert.informativeText = "The backup goes into “TubeShelf Backups” in the account you pick."
        alert.addButton(withTitle: "Back Up")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26))
        popup.addItems(withTitles: drives.map(\.accountName))
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let index = popup.indexOfSelectedItem
        return drives.indices.contains(index) ? drives[index] : drives[0]
    }

    private static func presentNoDrive(_ model: AppModel) {
        let alert = NSAlert()
        alert.messageText = "Google Drive for Desktop is not set up"
        alert.informativeText = "Install Google Drive for Desktop and sign in. The app then sees a folder in ~/Library/CloudStorage and this button writes straight into My Drive — no account linking."
        alert.addButton(withTitle: "Download Google Drive")
        alert.addButton(withTitle: "Choose Folder…")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "https://www.google.com/drive/download/") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            backUp(model)
        default:
            break
        }
    }

    // MARK: - Profiles

    /// Adds a backup as its own profile, so a friend's list never touches yours.
    static func importProfile(_ model: AppModel, onCreated: (() -> Void)? = nil) {
        let panel = NSOpenPanel()
        panel.title = "Add a profile from a backup"
        panel.prompt = "Add"
        panel.message = "The file becomes its own shelf. Your current profile is not changed."
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let contents: (library: Library, playlists: [PlaylistRecord])
        do {
            contents = try BackupService().readContents(from: url)
        } catch {
            model.flash("That backup could not be read: \(error.localizedDescription)")
            return
        }
        let incoming = contents.library

        if incoming.count == 0, contents.playlists.isEmpty {
            let warning = NSAlert()
            warning.alertStyle = .warning
            warning.messageText = "That backup is empty"
            warning.informativeText = "“\(url.lastPathComponent)” is a valid TubeShelf file, but it has no videos and no playlists. Add it as an empty profile anyway?"
            warning.addButton(withTitle: "Add Anyway")
            warning.addButton(withTitle: "Cancel")
            guard warning.runModal() == .alertFirstButtonReturn else { return }
        }

        let suggested = defaultProfileName(from: url)
        let summary = "\(incoming.count) videos · \(contents.playlists.count) playlists · imported from \(url.lastPathComponent)"
        guard let name = promptForName(
            title: "Name this profile",
            message: summary,
            initial: suggested,
            action: "Add Profile"
        ) else { return }

        do {
            try model.addProfile(
                name: name,
                library: incoming,
                playlists: contents.playlists,
                importedFrom: url.lastPathComponent
            )
            onCreated?()
        } catch {
            model.flash("Could not add the profile: \(error.localizedDescription)")
        }
    }

    static func promptForNewProfile(_ model: AppModel, onCreated: (() -> Void)? = nil) {
        guard let name = promptForName(
            title: "New empty profile",
            message: "A separate shelf with no videos. Your current profile is not changed.",
            initial: "New Shelf",
            action: "Create Profile"
        ) else { return }
        model.createEmptyProfile(named: name)
        onCreated?()
    }

    static func promptForName(
        title: String,
        message: String,
        initial: String,
        action: String
    ) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initial
        field.placeholderString = "Profile name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let cleaned = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? initial : cleaned
    }

    private static func defaultProfileName(from url: URL) -> String {
        if let parsed = ShelfBackup.profileName(fromFileName: url.lastPathComponent) {
            return parsed
        }
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix("TubeShelf ") {
            stem.removeFirst("TubeShelf ".count)
        }
        let timestamp = #"\s*\d{4}-\d{2}-\d{2} \d{2}\.\d{2}\.\d{2} \S+$"#
        stem = stem.replacingOccurrences(of: timestamp, with: "", options: .regularExpression)
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Imported Shelf" : stem
    }
}
