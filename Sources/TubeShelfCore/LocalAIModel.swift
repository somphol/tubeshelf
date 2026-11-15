import Foundation

/// An OpenAI-compatible chat endpoint. Point it at `fm serve`, Ollama or LM
/// Studio; the app only ever sends titles, channels, descriptions and the allowed
/// category names. Nothing is sent unless the person enables it.
public struct LocalAIConfig: Sendable, Equatable {
    public var baseURL: String
    public var model: String

    public init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    public var endpointURL: URL? {
        var text = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/chat/completions") {
            text += "/chat/completions"
        }
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }
        return url
    }
}

public enum LocalAIError: LocalizedError, Equatable {
    case badURL
    case http(Int)
    case emptyAnswer

    public var errorDescription: String? {
        switch self {
        case .badURL: "The local AI URL is not a valid http(s) address."
        case .http(let code): "The local AI server answered HTTP \(code)."
        case .emptyAnswer: "The local AI server returned no categories."
        }
    }
}

/// Minimal Chat Completions client. The model is constrained to the allowed
/// categories; anything else it says is discarded before it reaches the shelf.
public struct LocalAIClient: Sendable {
    private struct Message: Encodable {
        let role: String
        let content: String
    }

    private struct Request: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let stream: Bool
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    public let config: LocalAIConfig
    private let session: URLSession

    public init(config: LocalAIConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func suggest(
        title: String,
        channel: String,
        description: String,
        knownCategories: [String],
        limit: Int = 3
    ) async throws -> [String] {
        guard let url = config.endpointURL else { throw LocalAIError.badURL }

        let allowed = (TagTaxonomy.names + knownCategories)
            .uniquedCaseInsensitive()
            .sorted()
            .joined(separator: ", ")
        let body = Request(
            model: config.model,
            messages: [
                Message(role: "system", content: """
                You file YouTube videos into a personal library. Choose one to three \
                categories from the allowed list only. Return only the category names, \
                separated by commas, with no explanation and no other text. Fewer, \
                accurate categories are better than many loose ones.
                """),
                Message(role: "user", content: """
                Title: \(title)
                Channel: \(channel)
                Description: \(String(description.prefix(800)))
                Allowed categories: \(allowed)
                """)
            ],
            temperature: 0.2,
            stream: false
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LocalAIError.emptyAnswer }
        guard (200..<300).contains(http.statusCode) else { throw LocalAIError.http(http.statusCode) }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content else {
            throw LocalAIError.emptyAnswer
        }
        let tags = Self.parse(content: content, knownCategories: knownCategories, limit: limit)
        guard !tags.isEmpty else { throw LocalAIError.emptyAnswer }
        return tags
    }

    /// Split the answer, resolve every name against the built-in taxonomy or the
    /// person's own categories, and drop anything unknown.
    static func parse(content: String, knownCategories: [String], limit: Int = 3) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n;•")
        let punctuation = CharacterSet(charactersIn: "\"'`*_.-").union(.whitespacesAndNewlines)
        var resolved: [String] = []

        for piece in content.components(separatedBy: separators) {
            let cleaned = piece.trimmingCharacters(in: punctuation)
            guard !cleaned.isEmpty else { continue }
            if let match = TagNormalizer.taxonomyMatch(cleaned) {
                resolved.append(match)
                continue
            }
            guard let canonical = TagNormalizer.canonical(cleaned),
                  let known = knownCategories.first(where: {
                      $0.caseInsensitiveCompare(canonical) == .orderedSame
                  })
            else { continue }
            resolved.append(known)
        }

        return Array(TagNormalizer.merge(resolved).prefix(max(1, limit)))
    }
}

private extension Array where Element == String {
    func uniquedCaseInsensitive() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.lowercased()).inserted }
    }
}
