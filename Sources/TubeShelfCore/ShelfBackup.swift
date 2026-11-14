import Foundation

/// A portable copy of the shelf. The envelope carries a format marker and a
/// version so a future build can recognise its own files, while a plain
/// `library.json` is still accepted for people who back up by hand.
public struct ShelfBackup {
    public static let format = "tubeshelf.backup"
    public static let version = 1

    public enum BackupError: LocalizedError, Equatable {
        case notABackup
        case newerVersion(Int)
        case empty

        public var errorDescription: String? {
            switch self {
            case .notABackup:
                "That file is not a TubeShelf backup."
            case .newerVersion(let found):
                "That backup was written by a newer version of TubeShelf (format \(found)). Update the app first."
            case .empty:
                "That backup contains no videos."
            }
        }
    }

    private struct Envelope: Codable {
        let format: String
        let version: Int
        let exportedAt: Date
        let library: Library
    }

    private struct Probe: Decodable {
        let format: String?
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ library: Library, exportedAt: Date = Date()) throws -> Data {
        let envelope = Envelope(
            format: format,
            version: version,
            exportedAt: exportedAt,
            library: library
        )
        return try encoder().encode(envelope)
    }

    public static func decode(_ data: Data) throws -> Library {
        guard !data.isEmpty else { throw BackupError.empty }

        let probe = try? decoder().decode(Probe.self, from: data)
        if let marker = probe?.format {
            guard marker == format else { throw BackupError.notABackup }
            let envelope: Envelope
            do {
                envelope = try decoder().decode(Envelope.self, from: data)
            } catch {
                throw BackupError.notABackup
            }
            guard envelope.version <= version else {
                throw BackupError.newerVersion(envelope.version)
            }
            return envelope.library
        }

        // No marker: accept a raw library.json, which is what the app itself
        // writes on disk. Anything else is not ours — and a tolerant Library
        // decoder would happily turn arbitrary JSON into an empty shelf, which
        // would let a stray file wipe someone's data on restore.
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["videos"] is [Any]
        else { throw BackupError.notABackup }

        do {
            return try decoder().decode(Library.self, from: data)
        } catch {
            throw BackupError.notABackup
        }
    }

    /// `TubeShelf 2026-11-14 15.42.07 PST.json`
    ///
    /// Date, time to the second, and the zone, because two backups on the same
    /// day are otherwise indistinguishable once they are sitting in Drive. No
    /// colon or slash: both are hostile in filenames and in sync folders.
    public static func suggestedFileName(for date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = formatter.string(from: date)

        let rawZone = timeZone.abbreviation(for: date) ?? gmtOffsetName(for: timeZone, date: date)
        let safeZone = rawZone
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")

        return "TubeShelf \(stamp) \(safeZone).json"
    }

    private static func gmtOffsetName(for timeZone: TimeZone, date: Date) -> String {
        let seconds = timeZone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600
        let minutes = (abs(seconds) % 3600) / 60
        return String(format: "GMT%@%02d%02d", sign, hours, minutes)
    }
}

/// File-level backup and restore. Kept separate from the UI so it can be tested
/// and used from the command line.
public struct BackupService: Sendable {
    public init() {}

    public func write(_ library: Library, to url: URL) throws {
        let data = try ShelfBackup.encode(library)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    public func read(from url: URL) throws -> Library {
        let data = try Data(contentsOf: url)
        return try ShelfBackup.decode(data)
    }
}
