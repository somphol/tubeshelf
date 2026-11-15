import Foundation

public struct CategoryPair: Identifiable, Equatable, Sendable {
    public let first: String
    public let second: String
    public var id: String { "\(first)|\(second)" }

    public init(first: String, second: String) {
        self.first = first
        self.second = second
    }
}

/// Advice about the shape of the category list, never an automatic change.
public enum CategoryAudit {
    public struct Report: Sendable, Equatable {
        public let totalVideos: Int
        public let totalCategories: Int
        public let thinVideoCount: Int
        public let counts: [TagCount]
        public let lonely: [TagCount]
        public let nearDuplicates: [CategoryPair]
        public let catchAlls: [TagCount]
    }

    /// Combines video counts with one point per course carrying a tag.
    public static func report(
        videoCounts: [TagCount],
        playlistTags: [String],
        thinVideoCount: Int,
        totalVideos: Int
    ) -> Report {
        var tally: [String: Int] = [:]
        var spelling: [String: String] = [:]
        func add(_ name: String, _ count: Int) {
            let key = name.lowercased()
            tally[key, default: 0] += count
            if spelling[key] == nil { spelling[key] = name }
        }
        for tag in videoCounts { add(tag.name, tag.count) }
        for tag in playlistTags { add(tag, 1) }

        let counts = tally
            .map { TagCount(name: spelling[$0.key] ?? $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }

        let catchAllFloor = max(5, Int(Double(totalVideos) * 0.3))
        return Report(
            totalVideos: totalVideos,
            totalCategories: counts.count,
            thinVideoCount: thinVideoCount,
            counts: counts,
            lonely: counts.filter { $0.count == 1 },
            nearDuplicates: nearDuplicates(in: counts.map(\.name)),
            catchAlls: counts.filter { $0.count >= catchAllFloor }
        )
    }

    /// Flags names that are the same after normalisation, one contained in the
    /// other, or within a two-character edit.
    public static func nearDuplicates(in names: [String]) -> [CategoryPair] {
        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var pairs: [CategoryPair] = []

        for i in sorted.indices {
            for j in sorted.indices where j > i {
                let a = sorted[i], b = sorted[j]
                if isNearDuplicate(a, b) {
                    pairs.append(CategoryPair(first: a, second: b))
                }
            }
        }
        return pairs
    }

    static func isNearDuplicate(_ a: String, _ b: String) -> Bool {
        let na = normalize(a), nb = normalize(b)
        guard !na.isEmpty, !nb.isEmpty else { return false }
        if na == nb { return true }

        // "AI" vs "AI & Machine Learning": the short name must be a whole word.
        let short = na.count <= nb.count ? a : b
        let long = na.count <= nb.count ? b : a
        if wholeWordContained(short, in: long) { return true }

        let shorter = na.count <= nb.count ? na : nb
        let longer = na.count <= nb.count ? nb : na
        if shorter.count >= 4, longer.hasPrefix(shorter) { return true }

        guard min(na.count, nb.count) >= 5 else { return false }
        return distance(na, nb) <= 2
    }

    private static func wholeWordContained(_ word: String, in text: String) -> Bool {
        let needle = word.lowercased().trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return false }
        let words = text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.contains(needle)
    }

    static func normalize(_ name: String) -> String {
        let lowered = name.lowercased()
        let letters = lowered.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "",
            options: .regularExpression
        )
        // Crude singularisation so "Cars" and "Car" compare equal.
        if letters.count >= 4, letters.hasSuffix("s"),
           !letters.hasSuffix("ss"), !letters.hasSuffix("us"), !letters.hasSuffix("is") {
            return String(letters.dropLast())
        }
        return letters
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
