import XCTest
@testable import TubeShelfCore

final class CategoryAuditTests: XCTestCase {
    func testNormalisationIgnoresCaseSpacesAndPlurals() {
        XCTAssertEqual(CategoryAudit.normalize("Cars"), "car")
        XCTAssertEqual(CategoryAudit.normalize("C++"), "c")
        XCTAssertEqual(CategoryAudit.normalize("AI & Machine Learning"), "aimachinelearning")
    }

    func testNearDuplicates() {
        let pairs = CategoryAudit.nearDuplicates(in: [
            "Cars", "Car", "Design", "Desgin", "Math", "Mathematics", "Trigonometry"
        ])
        let flat = Set(pairs.map { [$0.first, $0.second].sorted().joined(separator: "|") })

        XCTAssertTrue(flat.contains("Car|Cars"))
        XCTAssertTrue(flat.contains("Desgin|Design"), "two-character typo should be flagged")
        XCTAssertTrue(flat.contains("Math|Mathematics"), "containment is a merge candidate")
        XCTAssertFalse(flat.contains("Design|Trigonometry"))
    }

    func testContainmentIsFlaggedForRealWords() {
        let pairs = CategoryAudit.nearDuplicates(in: ["AI", "AI & Machine Learning"])
        XCTAssertEqual(pairs.first?.first, "AI")
        XCTAssertEqual(pairs.first?.second, "AI & Machine Learning")
    }

    func testReportCombinesVideosAndCourses() {
        let report = CategoryAudit.report(
            videoCounts: [
                TagCount(name: "Math", count: 8),
                TagCount(name: "Cooking", count: 1),
                TagCount(name: "Education", count: 6)
            ],
            playlistTags: ["C++", "SWE", "Math"],
            thinVideoCount: 4,
            totalVideos: 20
        )

        XCTAssertEqual(report.totalCategories, 5)
        XCTAssertEqual(report.counts.first?.name, "Math")
        XCTAssertEqual(report.catchAlls.map(\.name), ["Math", "Education"])
        XCTAssertEqual(report.lonely.map(\.name), ["C++", "Cooking", "SWE"])
        XCTAssertEqual(report.thinVideoCount, 4)
    }

    func testEmptyListIsQuiet() {
        let report = CategoryAudit.report(
            videoCounts: [], playlistTags: [], thinVideoCount: 0, totalVideos: 0
        )
        XCTAssertTrue(report.lonely.isEmpty)
        XCTAssertTrue(report.nearDuplicates.isEmpty)
        XCTAssertTrue(report.catchAlls.isEmpty)
    }
}
