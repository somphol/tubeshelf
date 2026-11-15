import Foundation

/// Conservative extraction of a guest's name from a title or the opening of a
/// description. This only ever *suggests* an extra tag: it never removes,
/// replaces or reorders the category suggestions.
public struct GuestNameExtractor: Sendable {
    public init() {}

    /// Returns at most one plausible guest, or nil when the evidence is weak.
    public func guest(title: String, channel: String = "", description: String = "") -> String? {
        let channelKey = normalize(channel)
        for candidate in titleCandidates(title) + descriptionCandidates(description) {
            // Prefer the name without "Dr." / "Mr." / "PhD". A one-word stage
            // name such as "Dr. Dre" keeps its title because stripping would
            // leave a single word.
            for variant in [strippedTitles(candidate), candidate] {
                guard let name = validated(variant) else { continue }
                guard !overlapsChannel(name, channelKey: channelKey) else { continue }
                return name
            }
        }
        return nil
    }

    private static let honorifics: Set<String> = [
        "dr", "mr", "mrs", "ms", "mx", "prof", "professor",
        "sir", "dame", "lord", "lady", "rev", "reverend",
        "hon", "honorable", "judge", "justice", "capt", "captain",
        "col", "colonel", "gen", "general", "sen", "senator",
        "rep", "representative", "gov", "governor", "mayor"
    ]

    private static let credentials: Set<String> = [
        "phd", "md", "mba", "jd", "esq", "cpa", "rn", "dds", "dvm",
        "mph", "jr", "sr", "ii", "iii", "iv"
    ]

    /// Remove leading honorifics and trailing credentials, repeatedly.
    private func strippedTitles(_ raw: String) -> String {
        var words = raw
            .split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" })
            .map(String.init)
        while let first = words.first, Self.honorifics.contains(Self.core(first)) {
            words.removeFirst()
        }
        while let last = words.last, Self.credentials.contains(Self.core(last)) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }

    private static func core(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }

    // MARK: - Candidate windows

    private func titleCandidates(_ title: String) -> [String] {
        var out: [String] = []

        // "Marc Andreessen: The real AI boom…" and "A talk | Sam Altman".
        if let range = title.range(of: ":") {
            out.append(String(title[..<range.lowerBound]))
        }
        if let range = title.range(of: " | ") {
            out.append(String(title[..<range.lowerBound]))
            out.append(String(title[range.upperBound...]))
        }

        let patterns = [
            #"\b(?:with|feat\.?|featuring)\s+([\p{Lu}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){1,3})"#,
            #"\bguest:?\s+([\p{Lu}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){1,3})"#
        ]
        for pattern in patterns {
            out.append(contentsOf: captures(pattern, in: title))
        }
        return out
    }

    private func descriptionCandidates(_ description: String) -> [String] {
        // Only the opening matters; a name buried in credits or links is noise.
        let opening = String(description.prefix(600))
        var out: [String] = []

        let patterns = [
            #"(?im)^\s*guest:?\s+([\p{Lu}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){1,3})"#,
            #"\b(?:[Ii]n conversation with|[Jj]oined by|[Ss]its down with)\s+([\p{Lu}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){1,3})"#,
            // Opening bio: "Marc Andreessen is a founder, investor…"
            #"^\s*([\p{Lu}][\p{L}.'-]*(?:\s+[\p{Lu}][\p{L}.'-]*){1,3})\s+(?:is|joins|returns|sits down|talks|discusses)\b"#
        ]
        for pattern in patterns {
            out.append(contentsOf: captures(pattern, in: opening))
        }
        return out
    }

    // MARK: - Validation

    /// Words that turn a capitalised phrase into a title, a show or a topic.
    private static let blockedWords: Set<String> = [
        "the", "a", "an", "this", "that", "these", "those",
        "how", "why", "what", "when", "where", "who", "which",
        "new", "best", "top", "part", "episode", "ep", "vol", "volume",
        "podcast", "show", "interview", "conversation", "talk", "talks",
        "full", "live", "official", "trailer", "clip", "highlights",
        "machine", "learning", "artificial", "intelligence", "deep",
        "language", "model", "models", "ai", "ml", "llm", "llms",
        "day", "days", "year", "years", "world", "science", "history",
        "business", "money", "health", "news", "explained", "guide",
        "course", "tutorial", "review", "react", "reaction"
    ]

    private func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(
            in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        )
        guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }

        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\u{00A0}" }).map(String.init)
        guard (2...4).contains(words.count) else { return nil }

        for word in words {
            let core = word.trimmingCharacters(in: .punctuationCharacters)
            guard !core.isEmpty else { return nil }
            guard core.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) || $0 == "'" || $0 == "-" || $0 == "."
            }) else { return nil }
            guard let first = core.unicodeScalars.first,
                  CharacterSet.uppercaseLetters.contains(first)
            else { return nil }

            let hasLowercase = core.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
            let isInitial = core.count == 1 && word.hasSuffix(".")
            // Reject acronyms: "AI Explained" is a topic, not a person.
            guard hasLowercase || isInitial else { return nil }
            guard !Self.blockedWords.contains(core.lowercased()) else { return nil }
        }

        return words.joined(separator: " ")
    }

    /// A host's name is already the channel; suggesting it adds nothing.
    private func overlapsChannel(_ name: String, channelKey: String) -> Bool {
        guard !channelKey.isEmpty else { return false }
        let nameKey = normalize(name)
        guard !nameKey.isEmpty else { return true }
        if channelKey.contains(nameKey) || nameKey.contains(channelKey) { return true }
        let nameTokens = Set(nameKey.split(separator: " ").map(String.init))
        let channelTokens = Set(channelKey.split(separator: " ").map(String.init))
        return !nameTokens.isEmpty && nameTokens.isSubset(of: channelTokens)
    }

    // MARK: - Helpers

    private func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[captured])
        }
    }

    private func normalize(_ text: String) -> String {
        let folded = text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        let cleaned = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar)
                ? Character(scalar)
                : " "
        }
        return String(cleaned)
            .split(whereSeparator: { $0 == " " })
            .joined(separator: " ")
    }
}
