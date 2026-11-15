import Foundation

/// A category the app knows how to reason about. Kept as data so the AI prompt,
/// the sidebar icons, and the keyword fallback can never drift apart.
public struct VideoCategory: Sendable, Hashable, Identifiable {
    public let name: String
    public let symbol: String
    /// Words that are strong evidence on their own.
    public let keywords: [String]
    /// Words that appear across unrelated topics ("model", "market", "band").
    /// They can tip an already-plausible category but never carry one alone.
    public let weakKeywords: [String]
    /// A broader category this one belongs to. Suggesting "Trigonometry" also
    /// suggests "Math", which is how people actually file things.
    public let parent: String?

    public var id: String { name }

    public init(
        name: String,
        symbol: String,
        keywords: [String],
        weakKeywords: [String] = [],
        parent: String? = nil
    ) {
        self.name = name
        self.symbol = symbol
        self.keywords = keywords
        self.weakKeywords = weakKeywords
        self.parent = parent
    }
}

public enum TagTaxonomy {
    public static let unsorted = "Unsorted"

    public static let all: [VideoCategory] = [
        VideoCategory(name: "Programming", symbol: "chevron.left.forwardslash.chevron.right", keywords: [
            "code", "coding", "programming", "developer", "software", "swift", "swiftui", "python",
            "javascript", "typescript", "rust", "golang", "java", "kotlin", "c++", "html", "css",
            "api", "sdk", "compiler", "debugging", "refactor", "xcode", "git", "github", "backend",
            "frontend", "database", "sql", "server", "framework", "library", "terminal", "shell",
            "algorithm", "data structure", "web development", "app development", "devops", "docker",
            "kubernetes", "linux", "vim", "neovim", "regex", "tests", "unit test"
        ]),
        VideoCategory(name: "AI & Machine Learning", symbol: "brain.head.profile", keywords: [
            "ai", "artificial intelligence", "machine learning", "deep learning", "neural network",
            "llm", "large language model", "gpt", "chatgpt", "claude", "gemini", "transformer",
            "prompt", "prompting", "agent", "agents", "diffusion", "stable diffusion", "midjourney",
            "embedding", "fine tuning", "inference", "dataset", "pytorch", "tensorflow",
            "openai", "anthropic", "hugging face", "rag", "parameter", "frontier model",
            "deepseek", "llama", "qwen", "mistral", "gpt-4", "gpt-5"
        ], weakKeywords: [
            "model", "models", "training", "agent", "agents", "reasoning"
        ]),
        VideoCategory(name: "Design", symbol: "paintbrush.pointed", keywords: [
            "design", "designer", "ux", "ui", "figma", "sketch", "typography", "font", "logo",
            "branding", "brand", "layout", "colour", "color", "palette", "wireframe", "prototype",
            "motion design", "graphic design", "product design", "visual design", "icon", "grid"
        ]),
        VideoCategory(name: "Science", symbol: "atom", keywords: [
            "science", "physics", "chemistry", "biology", "space", "universe", "quantum", "nasa",
            "astronomy", "telescope", "planet", "mars", "evolution", "dna", "cell", "experiment",
            "research", "particle", "relativity", "black hole", "geology", "climate", "neuroscience"
        ]),
        VideoCategory(name: "Math", symbol: "function", keywords: [
            "math", "maths", "mathematics", "calculus", "algebra", "geometry", "trigonometry",
            "proof", "theorem", "equation", "statistics", "probability", "integral", "derivative",
            "linear algebra", "matrix", "topology", "number theory", "fraction", "graph theory"
        ]),
        VideoCategory(name: "Trigonometry", symbol: "triangle", keywords: [
            "trigonometry", "trigonometric", "trig", "unit circle", "sine", "cosine",
            "tangent", "radians", "law of sines", "law of cosines", "sohcahtoa",
            "sin", "cos", "tan"
        ], weakKeywords: ["angle", "triangle"], parent: "Math"),
        VideoCategory(name: "Calculus", symbol: "function", keywords: [
            "calculus", "derivative", "integral", "differentiation", "integration",
            "limits", "chain rule", "antiderivative", "taylor series", "differential equation"
        ], parent: "Math"),
        VideoCategory(name: "Geometry", symbol: "triangle.circle", keywords: [
            "geometry", "pythagorean", "polygon", "congruence", "similarity",
            "coordinate geometry", "circle theorem", "euclidean"
        ], parent: "Math"),
        VideoCategory(name: "Linear Algebra", symbol: "square.grid.3x3", keywords: [
            "linear algebra", "matrix", "matrices", "determinant", "eigenvalue",
            "eigenvector", "vector space", "basis", "span", "rank", "null space"
        ], parent: "Math"),
        VideoCategory(name: "Statistics", symbol: "chart.xyaxis.line", keywords: [
            "statistics", "probability", "standard deviation", "variance", "regression",
            "hypothesis testing", "confidence interval", "bayes", "distribution"
        ], parent: "Math"),
        VideoCategory(name: "Business", symbol: "chart.bar.xaxis", keywords: [
            "business", "startup", "founder", "entrepreneur", "marketing", "sales", "revenue",
            "growth", "saas", "pricing", "customer", "b2b", "b2c", "product market fit",
            "ecommerce", "agency", "freelance", "negotiation", "leadership", "hiring"
        ], weakKeywords: ["market", "strategy", "management"]),
        VideoCategory(name: "Finance", symbol: "banknote", keywords: [
            "finance", "financial", "invest", "investing", "stock", "stocks", "portfolio", "money",
            "wealth", "tax", "budget", "dividend", "etf", "index fund", "interest rate", "inflation",
            "retirement", "savings", "debt", "mortgage", "economics", "trading",
            "compound interest", "interest", "index funds", "fund", "budgeting", "net worth",
            "wall street", "stock market"
        ], weakKeywords: ["market", "stocks"]),
        VideoCategory(name: "Crypto & Web3", symbol: "bitcoinsign.circle", keywords: [
            "crypto", "cryptocurrency", "bitcoin", "ethereum", "blockchain", "web3", "defi",
            "nft", "solana", "wallet", "mining", "stablecoin", "smart contract"
        ]),
        VideoCategory(name: "Productivity", symbol: "checkmark.circle", keywords: [
            "productivity", "notes", "notetaking", "workflow", "notion", "obsidian", "habits",
            "routine", "focus", "time management", "gtd", "planning", "organise", "organize",
            "task", "to do", "calendar", "automation", "shortcut", "efficiency"
        ], weakKeywords: ["system", "workflow"]),
        VideoCategory(name: "Health & Fitness", symbol: "figure.run", keywords: [
            "health", "fitness", "workout", "gym", "training", "running", "marathon", "diet",
            "nutrition", "protein", "sleep", "weight loss", "muscle", "stretching", "yoga",
            "mobility", "recovery", "calories", "fasting", "longevity", "doctor", "medical"
        ]),
        VideoCategory(name: "Cooking", symbol: "fork.knife", keywords: [
            "recipe", "cook", "cooking", "baking", "bake", "kitchen", "food", "chef", "meal",
            "dinner", "breakfast", "bread", "sourdough", "pasta", "sauce", "dessert", "coffee",
            "restaurant", "flavour", "flavor", "ingredient", "sourdough starter"
        ]),
        VideoCategory(name: "Travel", symbol: "airplane", keywords: [
            "travel", "trip", "journey", "city guide", "hotel", "flight", "itinerary", "backpacking",
            "tourism", "vacation", "holiday", "tokyo", "kyoto", "paris", "london", "bangkok",
            "chiang mai", "new york", "airport", "visa", "digital nomad", "walking tour"
        ]),
        VideoCategory(name: "History", symbol: "book.closed", keywords: [
            "history", "historical", "ancient", "empire", "medieval", "war", "century", "dynasty",
            "archaeology", "civilization", "revolution", "rome", "egypt", "vikings", "cold war",
            "documentary history", "1914", "1945"
        ]),
        VideoCategory(name: "News & Politics", symbol: "newspaper", keywords: [
            "news", "politics", "political", "election", "government", "policy", "senate",
            "parliament", "president", "minister", "geopolitics", "protest", "law", "court",
            "supreme court", "breaking", "journalism", "reporter", "interview politics"
        ]),
        VideoCategory(name: "Education", symbol: "graduationcap", keywords: [
            "lecture", "course", "lesson", "tutorial", "explained", "class", "university",
            "learn", "learning", "teacher", "school", "exam", "revision",
            "beginner", "crash course", "masterclass"
        ], weakKeywords: ["class", "study"]),
        VideoCategory(name: "Music", symbol: "music.note", keywords: [
            "music", "song", "album", "guitar", "piano", "drums", "bass", "singing", "vocal",
            "concert", "live session", "producer", "production", "melody", "chord", "chords",
            "hip hop", "jazz", "classical", "orchestra", "singer", "lyrics"
        ], weakKeywords: ["band", "beat", "producer", "production"]),
        VideoCategory(name: "Film & Video", symbol: "film", keywords: [
            "film", "movie", "cinema", "cinematic", "camera", "filmmaking", "editing", "premiere",
            "after effects", "davinci", "director", "cinematography", "color grade", "screenplay",
            "documentary", "vlog", "youtube video", "b roll"
        ], weakKeywords: ["scene", "shot", "trailer", "production"]),
        VideoCategory(name: "Gaming", symbol: "gamecontroller", keywords: [
            "game", "gaming", "gameplay", "playthrough", "speedrun", "steam", "playstation", "ps5",
            "xbox", "nintendo", "switch", "minecraft", "elden ring", "zelda", "fortnite", "valorant",
            "league of legends", "boss fight", "rpg", "indie game", "review game"
        ]),
        VideoCategory(name: "DIY & Home", symbol: "hammer", keywords: [
            "diy", "woodworking", "carpentry", "home improvement", "home repair", "renovation",
            "gardening", "ikea", "furniture", "tools", "workshop",
            "plumbing", "electrical", "painting walls", "tiny house", "interior"
        ]),
        VideoCategory(name: "Photography", symbol: "camera", keywords: [
            "photography", "photo", "photos", "lens", "portrait", "lightroom", "aperture",
            "shutter", "exposure", "iso", "composition", "street photography", "landscape photo",
            "mirrorless", "dslr", "raw editing", "golden hour"
        ]),
        VideoCategory(name: "Cars", symbol: "car", keywords: [
            "car", "cars", "automotive", "tesla", "motorcycle",
            "electric vehicle", "horsepower", "turbo", "restoration", "car review", "track day"
        ], weakKeywords: ["engine", "driving"]),
        VideoCategory(name: "Sports", symbol: "sportscourt", keywords: [
            "sport", "sports", "football", "soccer", "basketball", "nba", "tennis", "cricket",
            "formula 1", "f1", "boxing", "ufc", "olympics", "world cup", "premier league",
            "training highlights", "match"
        ]),
        VideoCategory(name: "Writing", symbol: "pencil.line", keywords: [
            "writing", "writer", "book", "author", "essay", "novel", "storytelling", "story",
            "screenwriting", "publishing", "poetry", "journaling", "newsletter", "blog",
            "copywriting", "editing text"
        ], weakKeywords: ["story"]),
        VideoCategory(name: "Psychology", symbol: "brain", keywords: [
            "psychology", "mind", "mental health", "behaviour", "behavior", "therapy", "anxiety",
            "depression", "emotion", "cognitive", "bias", "meditation", "mindfulness", "self care",
            "trauma", "attachment", "relationship"
        ]),
        VideoCategory(name: "Language Learning", symbol: "character.bubble", keywords: [
            "language", "languages", "spanish", "french", "japanese", "korean", "chinese",
            "mandarin", "thai", "german", "italian", "grammar", "vocabulary", "pronunciation",
            "fluent", "duolingo", "learning english", "accent"
        ]),
        VideoCategory(name: "Talks & Podcasts", symbol: "mic", keywords: [
            "podcast", "episode", "interview", "fireside", "keynote", "ted talk",
            "tedx", "panel discussion", "q&a", "hosted by", "in conversation with"
        ])
    ]

    public static let names: [String] = all.map(\.name)

    private static let byName: [String: VideoCategory] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.name.lowercased(), $0) }
    )

    /// Spelling and shorthand variants the model or a person may produce.
    public static let aliases: [String: String] = [
        "ai": "AI & Machine Learning",
        "ml": "AI & Machine Learning",
        "machine learning": "AI & Machine Learning",
        "artificial intelligence": "AI & Machine Learning",
        "ai & ml": "AI & Machine Learning",
        "ai and machine learning": "AI & Machine Learning",
        "ai/ml": "AI & Machine Learning",
        "dev": "Programming",
        "development": "Programming",
        "software engineering": "Programming",
        "software": "Programming",
        "coding": "Programming",
        "code": "Programming",
        "web development": "Programming",
        "app development": "Programming",
        "maths": "Math",
        "mathematics": "Math",
        "physics": "Science",
        "science & tech": "Science",
        "science and technology": "Science",
        "money": "Finance",
        "investing": "Finance",
        "personal finance": "Finance",
        "crypto": "Crypto & Web3",
        "web3": "Crypto & Web3",
        "blockchain": "Crypto & Web3",
        "health": "Health & Fitness",
        "fitness": "Health & Fitness",
        "health and fitness": "Health & Fitness",
        "food": "Cooking",
        "recipes": "Cooking",
        "kitchen": "Cooking",
        "history": "History",
        "news": "News & Politics",
        "politics": "News & Politics",
        "education": "Education",
        "learning": "Education",
        "tutorial": "Education",
        "music": "Music",
        "film": "Film & Video",
        "video": "Film & Video",
        "filmmaking": "Film & Video",
        "gaming": "Gaming",
        "games": "Gaming",
        "diy": "DIY & Home",
        "home": "DIY & Home",
        "photography": "Photography",
        "car": "Cars",
        "automotive": "Cars",
        "sports": "Sports",
        "writing": "Writing",
        "books": "Writing",
        "psychology": "Psychology",
        "mental health": "Psychology",
        "language": "Language Learning",
        "language learning": "Language Learning",
        "podcast": "Talks & Podcasts",
        "podcasts": "Talks & Podcasts",
        "talks": "Talks & Podcasts",
        "design": "Design",
        "ux": "Design",
        "ui": "Design",
        "ux design": "Design",
        "ui design": "Design",
        "business": "Business",
        "startup": "Business",
        "startups": "Business",
        "travel": "Travel",
        "science": "Science",
        "productivity": "Productivity",
        "unsorted": unsorted,
        "uncategorized": unsorted,
        "other": unsorted
    ]

    public static func symbol(for tag: String) -> String {
        byName[tag.lowercased()]?.symbol ?? "tag"
    }

    public static func parent(of tag: String) -> String? {
        all.first { $0.name.caseInsensitiveCompare(tag) == .orderedSame }?.parent
    }

    /// Adds the broader category for anything that has one, preserving order and
    /// never duplicating.
    public static func withParents(_ tags: [String], limit: Int = 4) -> [String] {
        var result = tags
        for tag in tags {
            if let parent = parent(of: tag),
               !result.contains(where: { $0.caseInsensitiveCompare(parent) == .orderedSame }) {
                result.append(parent)
            }
        }
        return Array(result.prefix(max(limit, tags.count)))
    }

    public static func isKnown(_ tag: String) -> Bool {
        byName[tag.lowercased()] != nil
    }

    /// Everything a picker or the model prompt should offer, in a stable order.
    public static var pickableNames: [String] { names }

    public static func promptList() -> String {
        names.map { "- \($0)" }.joined(separator: "\n")
    }
}

public enum TagNormalizer {
    public static let maximumLength = 28

    /// Trims decoration, collapses whitespace, caps length. Returns nil for
    /// empty or useless input.
    public static func clean(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix("#") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.count > maximumLength {
            text = String(text.prefix(maximumLength)).trimmingCharacters(in: .whitespaces)
        }
        guard text.rangeOfCharacter(from: .alphanumerics) != nil else { return nil }
        // Title-case single-word tags so the shelf stays visually tidy, but leave
        // acronyms and multi-word tags exactly as the person typed them.
        return text
    }

    /// Normalises a name for storage. Deliberately does **not** apply aliases:
    /// someone typing "Learning" means a category called Learning, and silently
    /// rewriting it to "Education" made new categories impossible to create.
    /// Aliases are only used when interpreting model output — see `taxonomyMatch`.
    public static func canonical(_ raw: String) -> String? {
        guard let cleaned = clean(raw) else { return nil }
        let key = cleaned.lowercased()
        if let known = TagTaxonomy.all.first(where: { $0.name.lowercased() == key }) {
            return known.name
        }
        // "deep work" should read as "Deep work" on the shelf, while acronyms and
        // camel-case names keep their shape.
        if let first = cleaned.first, first.isLowercase {
            return first.uppercased() + cleaned.dropFirst()
        }
        return cleaned
    }

    /// Alias-aware lookup: "learning" → Education, "ai" → AI & Machine Learning.
    /// Used to reconcile what the on-device model returns, never for storage.
    public static func taxonomyMatch(_ raw: String) -> String? {
        guard let cleaned = clean(raw) else { return nil }
        let key = cleaned.lowercased()
        if let known = TagTaxonomy.all.first(where: { $0.name.lowercased() == key }) {
            return known.name
        }
        return TagTaxonomy.aliases[key]
    }

    /// Case-insensitive de-duplication that keeps the first spelling seen.
    public static func merge(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            guard let cleaned = canonical(tag) else { continue }
            let key = cleaned.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(cleaned)
        }
        return result
    }
}
