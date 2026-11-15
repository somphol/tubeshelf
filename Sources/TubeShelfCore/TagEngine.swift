import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum OnDeviceModelStatus: Sendable, Equatable {
    case available
    case unavailable(String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }

    public var shortLabel: String {
        switch self {
        case .available: "Apple Intelligence"
        case .unavailable: "Keyword fallback"
        }
    }

    public var detail: String {
        switch self {
        case .available:
            "Tags are suggested on this Mac by Apple's on-device model. Nothing leaves the machine."
        case .unavailable(let reason):
            reason
        }
    }
}

/// The one place the app asks for tag suggestions. Prefers the on-device model,
/// and always has a deterministic answer when it cannot be used.
public struct TagEngine: Sendable {
    public init() {}

    public static var status: OnDeviceModelStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return FoundationModelTagging.status
        }
        #endif
        return .unavailable("Apple Intelligence needs macOS 26 or newer.")
    }

    public func suggest(
        title: String,
        channel: String = "",
        description: String = "",
        channelHint: String? = nil,
        knownCategories: [String] = [],
        limit: Int = 3
    ) async -> TagSuggestion {
        let heuristic = HeuristicTagger().suggest(
            title: title,
            channel: channel,
            description: description,
            limit: limit,
            knownCategories: knownCategories
        )
        let fallback = applyingChannelHint(to: heuristic, hint: channelHint, knownCategories: knownCategories)

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), FoundationModelTagging.status.isAvailable {
            do {
                let raw = try await FoundationModelTagging.suggest(
                    title: title,
                    channel: channel,
                    description: description,
                    knownCategories: knownCategories,
                    limit: limit
                )
                let known = TagNormalizer.merge(raw.compactMap { resolve($0, knownCategories: knownCategories) })
                    .filter { name in
                        name != TagTaxonomy.unsorted
                            && (TagTaxonomy.isKnown(name)
                                || knownCategories.contains { $0.caseInsensitiveCompare(name) == .orderedSame })
                    }

                if !known.isEmpty {
                    // Trust the model's judgement, including when it returns a
                    // single category. Mixing in keyword guesses made the result
                    // less relevant, which is the thing this app is judged on.
                    let chosen = Array(known.prefix(max(1, min(limit, 3))))
                    return TagSuggestion(
                        tags: TagTaxonomy.withParents(chosen, limit: max(limit, chosen.count)),
                        source: .onDeviceModel
                    )
                }
            } catch {
                return TagSuggestion(
                    tags: fallback.tags,
                    source: .heuristic,
                    note: "Model unavailable: \(error.localizedDescription)"
                )
            }
        }
        #endif

        return fallback
    }

    /// When nothing in the title is decisive, fall back to what this channel is
    /// usually filed under. Only ever fills an empty answer — it never overrides
    /// a real match.
    private func applyingChannelHint(
        to suggestion: TagSuggestion,
        hint: String?,
        knownCategories: [String]
    ) -> TagSuggestion {
        guard suggestion.tags.isEmpty, let hint,
              let cleaned = TagNormalizer.canonical(hint)
        else { return suggestion }

        let isKnown = TagTaxonomy.isKnown(cleaned)
            || knownCategories.contains { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
        guard isKnown else { return suggestion }
        return TagSuggestion(tags: [cleaned], source: .heuristic, note: "Usual category for this channel")
    }

    /// The model may return an alias of a built-in category or one of the
    /// person's own categories. Resolve both, and drop anything else.
    private func resolve(_ raw: String, knownCategories: [String]) -> String? {
        if let match = TagNormalizer.taxonomyMatch(raw) { return match }
        guard let cleaned = TagNormalizer.canonical(raw) else { return nil }
        return knownCategories.first { $0.caseInsensitiveCompare(cleaned) == .orderedSame }
    }
}

#if canImport(FoundationModels)

@available(macOS 26.0, *)
@Generable
struct GeneratedTagList {
    @Guide(description: "One to three category names, copied exactly from the allowed list, most relevant first.")
    var tags: [String]
}

@available(macOS 26.0, *)
enum FoundationModelTagging {
    static var status: OnDeviceModelStatus {
        switch SystemLanguageModel(useCase: .contentTagging).availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .unavailable("This Mac is not eligible for Apple Intelligence, so tags come from the keyword classifier.")
            case .appleIntelligenceNotEnabled:
                return .unavailable("Apple Intelligence is turned off in System Settings, so tags come from the keyword classifier.")
            case .modelNotReady:
                return .unavailable("The on-device model is still getting ready. Tags come from the keyword classifier for now.")
            @unknown default:
                return .unavailable("The on-device model is unavailable. Tags come from the keyword classifier.")
            }
        }
    }

    static func suggest(
        title: String,
        channel: String,
        description: String,
        knownCategories: [String],
        limit: Int
    ) async throws -> [String] {
        let instructions = """
        You are the filing assistant for a personal YouTube library. You choose \
        categories for a video using only the allowed list. You never invent a \
        category, never explain yourself, and never repeat a category.

        Rules:
        - Pick between one and three categories, most relevant first.
        - Pick a category only when the title or channel clearly supports it.
        - Never add a category because of one incidental word in the description.
        - Fewer, accurate categories are better than many loose ones. When in \
        doubt, return a single category.

        Allowed categories:
        \(promptList(knownCategories))
        """

        let session = LanguageModelSession(
            model: SystemLanguageModel(useCase: .contentTagging),
            instructions: instructions
        )

        let trimmedDescription = String(description.prefix(600))
        var prompt = """
        Title: \(title)
        Channel: \(channel.isEmpty ? "unknown" : channel)
        """
        if !trimmedDescription.isEmpty {
            prompt += "\nDescription: \(trimmedDescription)"
        }
        prompt += "\n\nReturn one to three categories from the allowed list, most relevant first."

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedTagList.self,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 90)
        )

        return response.content.tags
    }

    private static func promptList(_ knownCategories: [String]) -> String {
        var names = TagTaxonomy.names
        for raw in knownCategories {
            guard let cleaned = TagNormalizer.canonical(raw),
                  cleaned.count >= 3,
                  !names.contains(where: { $0.caseInsensitiveCompare(cleaned) == .orderedSame })
            else { continue }
            names.append(cleaned)
        }
        if names.count > 60 { names = Array(names.prefix(60)) }
        return names.map { "- \($0)" }.joined(separator: "\n")
    }
}

#endif
