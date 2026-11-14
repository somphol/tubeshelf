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
