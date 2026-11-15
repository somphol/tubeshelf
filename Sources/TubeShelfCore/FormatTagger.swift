import Foundation

/// Adds a format tag that the keyword scorer misses because the episode language
/// lives outside the category keywords. Deliberately narrow: it only fires on
/// direct evidence of a show or interview, never on duration alone.
///
/// Currently the only format it knows is `Talks & Podcasts`.
public struct FormatTagger: Sendable {
    public init() {}

    /// - Parameter guest: a name already accepted by `GuestNameExtractor`, or nil.
    public func tags(
        title: String,
        channel: String = "",
        description: String = "",
        guest: String? = nil
    ) -> [String] {
        let headline = title.lowercased()
        let byline = channel.lowercased()
        let opening = String(description.prefix(700)).lowercased()

        // 1. Explicit self-description, the least ambiguous signal.
        if headline.contains("podcast") || byline.contains("podcast") || opening.contains("podcast") {
            return ["Talks & Podcasts"]
        }

        guard let guest, !guest.isEmpty else { return [] }

        // 2. A numbered episode with a named guest:
        //    "Joe Rogan Experience #2501 - Marc Andreessen" / "Episode 42: …".
        let episodePattern = #"(?:#\s*\d{1,5}\b|\b(?:ep|episode|part)\.?\s*\d{1,4}\b)"#
        if matches(episodePattern, in: headline) {
            return ["Talks & Podcasts"]
        }

        // 3. Two independent promo/show markers plus a named guest. A single
        //    "sponsor" mention can appear in a normal tutorial description.
        let markers = [
            "% off", "promo code", "sponsor", "sponsored by", "timestamps",
            "subscribe", "apple podcasts", "spotify", "patreon", "guest"
        ]
        let hits = markers.filter { opening.contains($0) }.count
        return hits >= 2 ? ["Talks & Podcasts"] : []
    }

    private func matches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
