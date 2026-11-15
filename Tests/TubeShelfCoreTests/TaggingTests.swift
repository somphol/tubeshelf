import XCTest
@testable import TubeShelfCore

final class TaggingTests: XCTestCase {
    func testTaxonomyIsCleanAndUnique() {
        let names = TagTaxonomy.names
        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, names.count, "duplicate category names")
        XCTAssertFalse(names.contains(TagTaxonomy.unsorted))
        XCTAssertGreaterThanOrEqual(names.count, 20)
        for category in TagTaxonomy.all {
            XCTAssertFalse(category.keywords.isEmpty, "\(category.name) has no keywords")
            XCTAssertFalse(category.symbol.isEmpty)
        }
    }

    func testCanonicalNeverRewritesWhatSomeoneTyped() {
        // Storage keeps the intent: a new category called Learning is allowed even
        // though "learning" is an alias for Education.
        XCTAssertEqual(TagNormalizer.canonical("Learning"), "Learning")
        XCTAssertEqual(TagNormalizer.canonical("learning"), "Learning")
        XCTAssertEqual(TagNormalizer.canonical("ai"), "Ai")
        XCTAssertEqual(TagNormalizer.canonical("  #design "), "Design")
        XCTAssertEqual(TagNormalizer.canonical("maths"), "Maths")
        XCTAssertNil(TagNormalizer.canonical("   "))
        XCTAssertNil(TagNormalizer.canonical("#"))
        XCTAssertEqual(TagNormalizer.canonical("deep work"), "Deep work")
        XCTAssertEqual(TagNormalizer.canonical("iOS development"), "IOS development")
    }

    func testTaxonomyMatchStillResolvesAliasesForModelOutput() {
        XCTAssertEqual(TagNormalizer.taxonomyMatch("ai"), "AI & Machine Learning")
        XCTAssertEqual(TagNormalizer.taxonomyMatch("Machine Learning"), "AI & Machine Learning")
        XCTAssertEqual(TagNormalizer.taxonomyMatch("learning"), "Education")
        XCTAssertEqual(TagNormalizer.taxonomyMatch("Design"), "Design")
        XCTAssertNil(TagNormalizer.taxonomyMatch("Learning Design"))
    }

    func testMergeIsCaseInsensitiveAndKeepsFirstSpelling() {
        let merged = TagNormalizer.merge(["Design", "design", "AI", "ai", "Cooking"])
        XCTAssertEqual(merged, ["Design", "AI", "Cooking"])
    }

    func testHeuristicClassifiesObviousTitles() {
        let tagger = HeuristicTagger()
        let cases: [(String, String)] = [
            ("SwiftUI concurrency: actors and tasks in Xcode", "Programming"),
            ("How to bake sourdough bread at home", "Cooking"),
            ("Apple's on-device LLM explained", "AI & Machine Learning"),
            ("Road trip through Tokyo: a travel guide", "Travel"),
            ("Mortal Kombat speedrun world record", "Gaming"),
            ("Dave Brubeck jazz piano transcription", "Music"),
            ("Roman empire: the fall of Rome", "History"),
            ("Compound interest and index funds for beginners", "Finance")
        ]
        for (title, expected) in cases {
            let suggestion = tagger.suggest(title: title)
            XCTAssertTrue(
                suggestion.tags.contains(expected),
                "\(title) → \(suggestion.tags), expected \(expected)"
            )
        }
    }

    func testHeuristicFallsBackToNoTags() {
        let suggestion = HeuristicTagger().suggest(title: "Conversation with my neighbour about the weather")
        XCTAssertTrue(suggestion.tags.isEmpty)
        XCTAssertEqual(suggestion.source, .heuristic)
    }

    func testHeuristicRespectsLimitAndRanksTitleOverDescription() {
        let suggestion = HeuristicTagger().suggest(
            title: "Python tutorial for beginners",
            description: "A long description that also mentions cooking, gardening and travel.",
            limit: 2
        )
        XCTAssertLessThanOrEqual(suggestion.tags.count, 2)
        XCTAssertEqual(suggestion.tags.first, "Education")
    }

    func testMathSubtopicsAreSuggestedAlongsideMath() {
        let suggestion = HeuristicTagger().suggest(
            title: "Trigonometry - Easy to understand 3D animation",
            channel: "Physics Videos by Eugene Khutoryansky"
        )
        XCTAssertTrue(suggestion.tags.contains("Math"), "got \(suggestion.tags)")
        XCTAssertTrue(suggestion.tags.contains("Trigonometry"), "got \(suggestion.tags)")

        let calculus = HeuristicTagger().suggest(title: "The essence of calculus: derivatives and integrals")
        XCTAssertTrue(calculus.tags.contains("Calculus"), "got \(calculus.tags)")
    }

    func testPluralsMatchSingularKeywords() {
        let suggestion = HeuristicTagger().suggest(
            title: "Binomial distributions | Probabilities of probabilities, part 1"
        )
        XCTAssertTrue(suggestion.tags.contains("Statistics"), "got \(suggestion.tags)")
        XCTAssertTrue(suggestion.tags.contains("Math"), "parent category should ride along")
    }

    func testStemmingDoesNotInventNewsFromNew() {
        let suggestion = HeuristicTagger().suggest(title: "A brand new beginning")
        XCTAssertFalse(suggestion.tags.contains("News & Politics"), "got \(suggestion.tags)")
    }

    func testUserCategoriesAreMatchedByName() {
        let suggestion = HeuristicTagger().suggest(
            title: "How I structure a Deep Work session",
            knownCategories: ["Deep Work", "Math"]
        )
        XCTAssertTrue(suggestion.tags.contains("Deep Work"), "got \(suggestion.tags)")

        // A category that is not mentioned must not appear.
        let other = HeuristicTagger().suggest(
            title: "Sourdough bread for beginners",
            knownCategories: ["Deep Work"]
        )
        XCTAssertFalse(other.tags.contains("Deep Work"))
    }

    func testWeakWordsCannotCarryACategoryAlone() {
        let tagger = HeuristicTagger()
        // "model" is a weak AI word; a fashion video must not become AI.
        XCTAssertFalse(tagger.suggest(title: "How to become a fashion model in 2026").tags.contains("AI & Machine Learning"))
        // Production credits in the description must not create a Music tag.
        let credits = tagger.suggest(
            title: "SwiftUI essentials",
            channel: "Apple Developer",
            description: "Music by someone. Produced by someone else. Mixed by a third person."
        )
        XCTAssertFalse(credits.tags.contains("Music"))
        XCTAssertTrue(credits.tags.contains("Programming"))
    }

    func testBareLanguageDoesNotImplyLanguageLearning() {
        let tagger = HeuristicTagger()
        // The Stanford LLM lecture mentions "language" and "learning", but this
        // is AI, not foreign-language study.
        let lecture = tagger.suggest(
            title: "Stanford CS229 I Machine Learning I Building Large Language Models (LLMs)",
            channel: "Stanford Online"
        )
        XCTAssertTrue(lecture.tags.contains("AI & Machine Learning"), "\(lecture.tags)")
        XCTAssertFalse(lecture.tags.contains("Language Learning"), "\(lecture.tags)")

        XCTAssertTrue(
            tagger.suggest(title: "Learn Japanese: grammar for beginners").tags.contains("Language Learning")
        )
        XCTAssertTrue(
            tagger.suggest(title: "How to learn a language in 30 days").tags.contains("Language Learning")
        )
    }

    func testSuggestionsStayCloseToTheTopHit() {
        // One strong category must not drag along near-miss categories.
        let suggestion = HeuristicTagger().suggest(
            title: "Ten Minute History - The Fall of Rome",
            channel: "History Matters",
            description: "A short documentary about the Roman empire, cars, cooking, travel and music."
        )
        XCTAssertLessThanOrEqual(suggestion.tags.count, 2)
        XCTAssertTrue(suggestion.tags.contains("History"))
        XCTAssertFalse(suggestion.tags.contains("Cars"))
        XCTAssertFalse(suggestion.tags.contains("Music"))
    }

    func testGuestNameFromTitlePrefixAndDescription() {
        let extractor = GuestNameExtractor()
        XCTAssertEqual(
            extractor.guest(
                title: "Marc Andreessen: The real AI boom hasn’t even started yet",
                channel: "Lenny's Podcast",
                description: "Marc Andreessen is a founder, investor, and co-founder of Netscape."
            ),
            "Marc Andreessen"
        )
        XCTAssertEqual(
            extractor.guest(title: "Interview with Sam Altman", channel: "Talks at Google"),
            "Sam Altman"
        )
        XCTAssertEqual(
            extractor.guest(
                title: "The next platform shift",
                channel: "Lenny's Podcast",
                description: "In conversation with Bret Taylor about agents."
            ),
            "Bret Taylor"
        )
    }

    func testGuestTitlesAndCredentialsAreDropped() {
        let extractor = GuestNameExtractor()
        XCTAssertEqual(
            extractor.guest(title: "Dr. Marc Andreessen: The real AI boom"),
            "Marc Andreessen"
        )
        XCTAssertEqual(
            extractor.guest(title: "Prof. Dr. Sarah Drasner: CSS that scales"),
            "Sarah Drasner"
        )
        XCTAssertEqual(
            extractor.guest(title: "Interview with Sir David Attenborough"),
            "David Attenborough"
        )
        XCTAssertEqual(
            extractor.guest(title: "Marc Andreessen, PhD: The real AI boom"),
            "Marc Andreessen"
        )
        // A one-word stage name keeps its title rather than becoming "Dre".
        XCTAssertEqual(extractor.guest(title: "Dr. Dre: The recipe"), "Dr. Dre")
    }

    func testGuestNameRejectsHostsShowsAndTopics() {
        let extractor = GuestNameExtractor()
        // The host is the channel, not a guest.
        XCTAssertNil(extractor.guest(title: "Huberman Lab: How to sleep", channel: "Huberman Lab"))
        XCTAssertNil(extractor.guest(title: "Lex Fridman Podcast #400: AI", channel: "Lex Fridman"))
        // A show name and a topic are not people.
        XCTAssertNil(extractor.guest(title: "The Daily: A new election", channel: "The New York Times"))
        XCTAssertNil(extractor.guest(title: "How to Build a Startup", channel: "Y Combinator"))
        XCTAssertNil(extractor.guest(title: "AI & Machine Learning: What comes next", channel: "Stanford Online"))
    }

    func testGuestNameFromShowEpisodeDescription() {
        // Episodes often carry the guest only in the opening bio, not the title.
        XCTAssertEqual(
            GuestNameExtractor().guest(
                title: "Joe Rogan Experience #2501 - Marc Andreessen",
                channel: "PowerfulJRE",
                description: "Marc Andreessen is a co-founder and general partner at the venture capital firm Andreessen Horowitz."
            ),
            "Marc Andreessen"
        )
    }

    func testPodcastFormatIsDetectedFromEpisodeEvidence() {
        let tagger = FormatTagger()
        // Numbered episode plus a named guest.
        XCTAssertEqual(
            tagger.tags(
                title: "Joe Rogan Experience #2501 - Marc Andreessen",
                channel: "PowerfulJRE",
                description: "Marc Andreessen is a co-founder and general partner.",
                guest: "Marc Andreessen"
            ),
            ["Talks & Podcasts"]
        )
        // Explicit self-description needs no guest.
        XCTAssertEqual(
            tagger.tags(title: "The future of agents", channel: "Lenny's Podcast"),
            ["Talks & Podcasts"]
        )
        // A guest alone is not a format: a long tutorial is not a podcast.
        XCTAssertEqual(
            tagger.tags(
                title: "Build a server with Sarah Drasner",
                channel: "Conference",
                description: "A practical walkthrough.",
                guest: "Sarah Drasner"
            ),
            []
        )
        XCTAssertEqual(
            tagger.tags(title: "Joe Rogan Experience #2501 - Marc Andreessen", guest: nil),
            []
        )
    }

    func testPodcastFormatIsAppendedForTheJREExample() async {
        let suggestion = await TagEngine().suggest(
            title: "Joe Rogan Experience #2501 - Marc Andreessen",
            channel: "PowerfulJRE",
            description: "Marc Andreessen is a co-founder and general partner at the venture capital firm Andreessen Horowitz."
        )
        XCTAssertTrue(suggestion.tags.contains("Talks & Podcasts"), "\(suggestion.tags)")
        XCTAssertTrue(suggestion.tags.contains("Marc Andreessen"), "\(suggestion.tags)")
    }

    func testGuestNameIsAppendedWithoutDisplacingCategories() async {
        let suggestion = await TagEngine().suggest(
            title: "Marc Andreessen: The real AI boom hasn’t even started yet",
            channel: "Lenny's Podcast",
            description: "Marc Andreessen is a founder, investor, and co-founder of Netscape."
        )
        XCTAssertTrue(suggestion.tags.contains("AI & Machine Learning"), "\(suggestion.tags)")
        XCTAssertEqual(suggestion.tags.last, "Marc Andreessen", "\(suggestion.tags)")
    }

    func testEngineFallsBackWithoutModel() async {
        // On a machine without Apple Intelligence this exercises the fallback
        // path; with it enabled the assertion still holds because the answer is
        // a known category.
        let suggestion = await TagEngine().suggest(title: "Rust ownership and borrowing explained")
        XCTAssertFalse(suggestion.tags.isEmpty)
        XCTAssertTrue(TagTaxonomy.isKnown(suggestion.tags[0]))
    }

    func testSearchNormalisation() {
        XCTAssertEqual(SearchText.normalize("  Café   Society "), "cafe society")
        XCTAssertTrue(SearchText.matches(needle: "swift actor", haystack: "Actors in Swift 6"))
        XCTAssertFalse(SearchText.matches(needle: "rust actor", haystack: "Actors in Swift 6"))
    }
}
