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
        panel.nameFieldStringValue = ShelfBackup.suggestedFileName()
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

        let incoming: Library
        do {
            incoming = try BackupService().read(from: url)
        } catch {
            model.flash("Restore failed: \(error.localizedDescription)")
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Restore \(incoming.count) video\(incoming.count == 1 ? "" : "s")?"
        alert.informativeText = """
        This replaces the current profile (“\(model.currentProfile?.name ?? "shelf")”, \(model.library.count) videos).
        The current library is copied aside in Application Support before anything changes.
        """
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try model.restore(from: url)
        } catch {
            model.flash("Restore failed: \(error.localizedDescription)")
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

        let incoming: Library
        do {
            incoming = try BackupService().read(from: url)
        } catch {
            model.flash("That backup could not be read: \(error.localizedDescription)")
            return
        }

        let suggested = defaultProfileName(from: url)
        guard let name = promptForName(
            title: "Name this profile",
            message: "\(incoming.count) videos · imported from \(url.lastPathComponent)",
            initial: suggested,
            action: "Add Profile"
        ) else { return }

        do {
            try model.addProfile(name: name, library: incoming, importedFrom: url.lastPathComponent)
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
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasPrefix("TubeShelf ") {
            stem.removeFirst("TubeShelf ".count)
        }
        stem = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return stem.isEmpty ? "Imported Shelf" : stem
    }
}
