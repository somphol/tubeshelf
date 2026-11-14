import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TubeShelfCore

/// File panels and the restore confirmation live here so the Settings window and
/// the menu commands run exactly the same code.
@MainActor
enum BackupActions {
    static func backUp(_ model: AppModel) {
        let panel = NSSavePanel()
        panel.title = "Back up your shelf"
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
        panel.title = "Restore from a TubeShelf backup"
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
        This replaces your current shelf (\(model.library.count) videos).
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
}
