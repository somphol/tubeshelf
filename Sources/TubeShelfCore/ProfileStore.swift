import Foundation

/// A named shelf. Each profile owns a directory, so switching profiles can never
/// touch another profile's videos.
public struct Profile: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var importedFrom: String?

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        importedFrom: String? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = Video.normalized(createdAt)
        self.importedFrom = importedFrom
    }

    public var subtitle: String {
        if let importedFrom {
            return "Imported from \(importedFrom)"
        }
        return "Created \(createdAt.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
}

/// Profile storage on disk:
///
///     Application Support/TubeShelf/
///     ├── Profiles/<uuid>/profile.json
///     ├── Profiles/<uuid>/library.json
///     ├── Thumbnails/               (shared cache, rebuilt any time)
///     └── library.json              (pre-profile file, adopted and left as backup)
///
/// There is deliberately no central index: the profiles folder *is* the truth, so
/// a lost or corrupt index cannot hide anyone's shelf.
public struct ProfileStore: Sendable {
    public let root: URL

    public init(root: URL = ProfileStore.defaultRoot()) {
        self.root = root
    }

    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("TubeShelf", isDirectory: true)
    }

    public var profilesFolder: URL {
        root.appendingPathComponent("Profiles", isDirectory: true)
    }

    public var legacyLibraryURL: URL {
        root.appendingPathComponent("library.json")
    }

    public func directory(for profile: Profile) -> URL {
        profilesFolder.appendingPathComponent(profile.id.uuidString, isDirectory: true)
    }

    public func libraryStore(for profile: Profile) -> LibraryStore {
        LibraryStore(directory: directory(for: profile))
    }

    // MARK: - Reading

    /// Every profile, oldest first. Adopts a pre-profile `library.json` the first
    /// time it runs, and never deletes that original file.
    public func profiles() throws -> [Profile] {
        let found = try scan()
        if !found.isEmpty { return found }

        if FileManager.default.fileExists(atPath: legacyLibraryURL.path) {
            if let adopted = try? adoptLegacyLibrary() {
                return [adopted]
            }
        }

        let fresh = try create(name: "My Shelf", library: Library(), importedFrom: nil)
        return [fresh]
    }

    private func scan() throws -> [Profile] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: profilesFolder.path) else { return [] }

        let entries = try manager.contentsOfDirectory(
            at: profilesFolder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var profiles: [Profile] = []
        for entry in entries {
            guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let metaURL = entry.appendingPathComponent("profile.json")
            guard let data = try? Data(contentsOf: metaURL),
                  var profile = try? JSONDecoder.profile.decode(Profile.self, from: data)
            else { continue }
            // The folder name is the identity; repair a mismatch rather than
            // creating a duplicate profile.
            if let folderID = UUID(uuidString: entry.lastPathComponent) {
                profile.id = folderID
            }
            profiles.append(profile)
        }

        return profiles.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.name < rhs.name : lhs.createdAt < rhs.createdAt
        }
    }

    private func adoptLegacyLibrary() throws -> Profile {
        let data = try Data(contentsOf: legacyLibraryURL)
        let library = try JSONDecoder.tolerant.decode(Library.self, from: data)
        return try create(name: "My Shelf", library: library, importedFrom: "your pre-profile library")
    }

    // MARK: - Writing

    public func create(name: String, library: Library, importedFrom: String?) throws -> Profile {
        let profile = Profile(name: name, importedFrom: importedFrom)
        let directory = directory(for: profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try JSONEncoder.profile.encode(profile)
            .write(to: directory.appendingPathComponent("profile.json"), options: .atomic)
        try libraryStore(for: profile).save(library)
        return profile
    }

    public func saveMetadata(_ profile: Profile) throws {
        let directory = directory(for: profile)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.profile.encode(profile)
            .write(to: directory.appendingPathComponent("profile.json"), options: .atomic)
    }

    /// Moves the profile folder to the Trash rather than deleting it outright.
    @discardableResult
    public func trash(_ profile: Profile) throws -> URL {
        var trashed: NSURL?
        try FileManager.default.trashItem(at: directory(for: profile), resultingItemURL: &trashed)
        return (trashed as URL?) ?? directory(for: profile)
    }

    /// "Trip" → "Trip 2" when the name is taken, so imports never collide.
    public func uniqueName(_ base: String, among profiles: [Profile]) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = trimmed.isEmpty ? "Shelf" : trimmed
        var candidate = seed
        var counter = 2
        while profiles.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
            candidate = "\(seed) \(counter)"
            counter += 1
        }
        return candidate
    }
}

extension JSONEncoder {
    static var profile: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var profile: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// Used when adopting a legacy file that may predate newer fields.
    static var tolerant: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
