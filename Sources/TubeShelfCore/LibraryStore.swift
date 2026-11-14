import Foundation

public struct LibraryStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("library.json") }

    public init(directory: URL = LibraryStore.defaultDirectory()) {
        self.directory = directory
    }

    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("TubeShelf", isDirectory: true)
    }

    public func load() throws -> Library {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return Library()
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(Library.self, from: data)
        } catch {
            // A corrupt file should not destroy the app. Move it aside so the
            // person can recover it by hand, then start clean.
            let backup = directory.appendingPathComponent("library-corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return Library()
        }
    }

    public func save(_ library: Library) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)
        try data.write(to: fileURL, options: .atomic)
    }
}
