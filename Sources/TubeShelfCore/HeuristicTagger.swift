import Foundation

public enum TagSource: String, Sendable, Codable {
    case onDeviceModel
    case localModel
    case heuristic
    case manual

    public var label: String {
        switch self {
        case .onDeviceModel: "Apple Intelligence"
        case .localModel: "Local AI"
        case .heuristic: "Keyword match"
        case .manual: "Manual"
        }
    }
}

public struct TagSuggestion: Sendable, Equatable {
    public var tags: [String]
    public var source: TagSource
    public var note: String

    public init(tags: [String], source: TagSource, note: String = "") {
        self.tags = tags
        self.source = source
        self.note = note
    }

    public var isEmpty: Bool { tags.isEmpty }
}

/// Deterministic, offline classifier. Runs when Apple Intelligence is off, when
/// the model errors, or in tests. Scoring: title hits count most, then channel,
/// then description.
public struct HeuristicTagger: Sendable {
    public init() {}

    public func suggest(
        title: String,
        channel: String = "",
        description: String = "",
        limit: Int = 4,
        knownCategories: [String] = []
    ) -> TagSuggestion {
        let headline = TextMatcher.normalize(title)
        let byline = TextMatcher.normalize(channel)
        let body = TextMatcher.normalize(description)

        // The person's own categories count as topics too: once "Trigonometry"
        // exists on the shelf, a trig video should suggest it by name even though
        // the built-in taxonomy knows nothing about it.
        var candidates: [(name: String, keywords: [String], weakKeywords: [String])] =
            TagTaxonomy.all.map { ($0.name, $0.keywords, $0.weakKeywords) }

        let taxonomyKeys = Set(TagTaxonomy.names.map { $0.lowercased() })
        for raw in knownCategories {
            guard let cleaned = TagNormalizer.canonical(raw),
                  cleaned.count >= 3,
                  !taxonomyKeys.contains(cleaned.lowercased())
            else { continue }
            if candidates.contains(where: { $0.name.caseInsensitiveCompare(cleaned) == .orderedSame }) {
                continue
            }
            candidates.append((cleaned, [cleaned], []))
        }

        var scored: [(name: String, score: Int)] = []
        for category in candidates {
            var strongTitle = 0
            var strongChannel = 0
            var strongBody = 0
            for keyword in category.keywords {
                if TextMatcher.contains(keyword, in: headline) { strongTitle += 1 }
                if TextMatcher.contains(keyword, in: byline) { strongChannel += 1 }
                if TextMatcher.contains(keyword, in: body) { strongBody += 1 }
            }

            var weakTitle = 0
            var weakChannel = 0
            var weakBody = 0
            for keyword in category.weakKeywords {
                if TextMatcher.contains(keyword, in: headline) { weakTitle += 1 }
                else if TextMatcher.contains(keyword, in: byline) { weakChannel += 1 }
                else if TextMatcher.contains(keyword, in: body) { weakBody += 1 }
            }

            // Title evidence dominates; weak words can tip a plausible hit but
            // cannot carry a category on their own. Description credits such as
            // "music by …" can never outvote the title.
            let score = 4 * min(strongTitle, 2)
                + 2 * min(strongChannel, 1)
                + 2 * min(strongBody, 2)
                + min(weakTitle, 2)
                + min(weakChannel, 1)
                + min(weakBody, 1)

            let anchored = strongTitle > 0 || strongChannel > 0 || weakTitle > 0
            if score >= 4, anchored {
                scored.append((category.name, score))
            }
        }

        let ranked = scored.sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.name < rhs.name : lhs.score > rhs.score
        }

        guard let topScore = ranked.first?.score else {
            return TagSuggestion(tags: [], source: .heuristic, note: "No confident match")
        }

        // Relevance margin: a tag must be at least 60% as strong as the best one.
        // This is what stops "one real category plus three near-misses".
        let floor = Int((Double(topScore) * 0.6).rounded(.up))
        let ordered = ranked
            .filter { $0.score >= floor }
            .prefix(max(1, min(limit, 3)))
            .map(\.name)

        return TagSuggestion(
            tags: TagTaxonomy.withParents(Array(ordered), limit: max(limit, ordered.count)),
            source: .heuristic
        )
    }
}

enum TextMatcher {
    /// Lowercases and turns punctuation into spaces so "C++" and "c++" and
    /// "c++," all agree, while keeping letter runs intact.
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let spaced = lowered.replacingOccurrences(
            of: "[^\\p{L}\\p{N}+#]+",
            with: " ",
            options: .regularExpression
        )
        return " " + spaced.trimmingCharacters(in: .whitespaces) + " "
    }

    static func contains(_ keyword: String, in normalizedText: String) -> Bool {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Non-Latin scripts (Thai, CJK) do not use spaces between words, so a
        // boundary match would never fire. Fall back to a plain substring test.
        if trimmed.unicodeScalars.contains(where: { $0.value > 0x024F }) {
            return normalize(normalizedText).contains(normalize(trimmed).trimmingCharacters(in: .whitespaces))
        }

        let needle = tokens(trimmed).map(stem)
        let haystack = tokens(normalizedText).map(stem)
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        for start in 0...(haystack.count - needle.count) {
            if Array(haystack[start..<start + needle.count]) == needle { return true }
        }
        return false
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split(separator: " ").map(String.init)
    }

    /// Very light singularisation so "distributions" matches "distribution" and
    /// "probabilities" matches "probability". Short words are left alone, which
    /// keeps "news" from becoming "new".
    static func stem(_ word: String) -> String {
        guard word.count >= 5 else { return word }
        if word.hasSuffix("ies"), word.count > 5 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("ss") {
            return word
        }
        if word.hasSuffix("s") {
            return String(word.dropLast())
        }
        return word
    }
}
