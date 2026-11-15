import Foundation

/// A Google Drive account mounted by Google Drive for Desktop.
public struct CloudDrive: Equatable, Sendable, Identifiable {
    /// Folder name as mounted, e.g. `GoogleDrive-someone@gmail.com`.
    public let identifier: String
    /// The `My Drive` folder inside it.
    public let myDrive: URL

    public var id: String { identifier }

    /// `someone@gmail.com`, or the raw folder name if it is not an address.
    public var accountName: String {
        identifier.hasPrefix("GoogleDrive-")
            ? String(identifier.dropFirst("GoogleDrive-".count))
            : identifier
    }

    public init(identifier: String, myDrive: URL) {
        self.identifier = identifier
        self.myDrive = myDrive
    }
}

/// Finds Google Drive folders without OAuth. Drive for Desktop mounts accounts
/// under `~/Library/CloudStorage/GoogleDrive-<account>/My Drive`; if that folder
/// exists, writing into it is just a file write and Drive syncs it.
public struct CloudDriveLocator: Sendable {
    public static let backupFolderName = "TubeShelf Backups"

    public let root: URL

    public init(root: URL = CloudDriveLocator.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/CloudStorage", isDirectory: true)
    }

    public func googleDrives() -> [CloudDrive] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let drives: [CloudDrive] = entries.compactMap { entry in
            let name = entry.lastPathComponent
            guard name.hasPrefix("GoogleDrive-"),
                  (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return nil }

            let myDrive = entry.appendingPathComponent("My Drive", isDirectory: true)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: myDrive.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else { return nil }

            return CloudDrive(identifier: name, myDrive: myDrive)
        }

        return drives.sorted { $0.identifier.localizedCaseInsensitiveCompare($1.identifier) == .orderedAscending }
    }

    /// Creates `<My Drive>/TubeShelf Backups` on demand and returns it.
    @discardableResult
    public func backupFolder(in drive: CloudDrive) throws -> URL {
        let folder = drive.myDrive.appendingPathComponent(Self.backupFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
