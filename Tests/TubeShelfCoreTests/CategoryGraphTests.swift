import XCTest
@testable import TubeShelfCore

final class CategoryGraphTests: XCTestCase {
    func testNodesUseCountsAndScaleArea() {
        let counts = [
            TagCount(name: "AI & Machine Learning", count: 100),
            TagCount(name: "Math", count: 25),
            TagCount(name: "Cooking", count: 1)
        ]
        let graph = CategoryGraph(counts: counts, videoTags: [], includeIsolated: true)

        XCTAssertEqual(graph.nodes.map(\.name), ["AI & Machine Learning", "Cooking", "Math"])
        XCTAssertEqual(graph.maxCount, 100)
        let ai = graph.nodes.first { $0.name == "AI & Machine Learning" }!
        let cooking = graph.nodes.first { $0.name == "Cooking" }!
        XCTAssertGreaterThan(ai.radius, cooking.radius)
        XCTAssertEqual(cooking.radius, 5.5, accuracy: 0.001, "the floor keeps small nodes clickable")
    }

    func testUnlinkedCategoriesAreHiddenUnlessRequested() {
        let counts = ["A", "B", "C"].map { TagCount(name: $0, count: 1) }
        let graph = CategoryGraph(counts: counts, videoTags: [["A", "B"]])
        XCTAssertEqual(graph.nodes.map(\.id), ["a", "b"])
        XCTAssertEqual(graph.hiddenCount, 1)

        let all = CategoryGraph(counts: counts, videoTags: [["A", "B"]], includeIsolated: true)
        XCTAssertEqual(all.nodes.count, 3)
        XCTAssertEqual(all.hiddenCount, 1)
    }

    func testEdgesWeighSharedVideos() {
        let counts = [
            TagCount(name: "AI", count: 3),
            TagCount(name: "Math", count: 2),
            TagCount(name: "Cooking", count: 1)
        ]
        let videos = [
            ["AI", "Math"],
            ["AI", "Math"],
            ["AI"]
        ]
        let graph = CategoryGraph(counts: counts, videoTags: videos)

        XCTAssertEqual(graph.edges.count, 1)
        XCTAssertEqual(graph.edges[0].shared, 2)
        XCTAssertEqual(Set([graph.edges[0].a, graph.edges[0].b]), ["ai", "math"])
    }

    func testEachNodeKeepsOnlyItsStrongestLinks() {
        let counts = ["A", "B", "C", "D", "E"].map { TagCount(name: $0, count: 10) }
        let videos = [
            ["A", "B"], ["A", "B"], ["A", "B"],
            ["A", "C"], ["A", "C"],
            ["A", "D"], ["A", "E"]
        ]
        let graph = CategoryGraph(counts: counts, videoTags: videos, maxEdgesPerNode: 1)
        let aEdges = graph.edges.filter { $0.a == "a" || $0.b == "a" }
        XCTAssertEqual(aEdges.count, 1)
        XCTAssertEqual(aEdges[0].shared, 3)
    }

    func testDenseGraphsRaiseTheSharedThreshold() {
        let counts = (0..<12).map { TagCount(name: "C\($0)", count: 1) }
        // Every video pairs a different combination, producing many one-video links.
        let videos = (0..<12).map { i in ["C\(i)", "C\((i + 1) % 12)"] }
        let graph = CategoryGraph(counts: counts, videoTags: videos, maxEdgesPerNode: 2)
        XCTAssertTrue(graph.edges.allSatisfy { $0.shared >= 1 })
        XCTAssertLessThanOrEqual(graph.edges.count, 24)
    }

    func testLayoutIsDeterministicAndInsideBounds() {
        let counts = ["A", "B", "C", "D", "E", "F"].map { TagCount(name: $0, count: 5) }
        let graph = CategoryGraph(
            counts: counts,
            videoTags: [["A", "B"], ["C", "D"], ["E", "F"], ["A", "C"]]
        )
        let first = graph.layout()
        let second = graph.layout()
        XCTAssertEqual(first, second)

        for point in first.values {
            XCTAssertTrue((0.03...0.97).contains(point.x), "\(point)")
            XCTAssertTrue((0.03...0.97).contains(point.y), "\(point)")
        }
    }

    func testSeparationPushesLargeNodesApart() {
        let counts = ["A", "B", "C"].map { TagCount(name: $0, count: 100) }
        let graph = CategoryGraph(
            counts: counts,
            videoTags: [["A", "B"], ["B", "C"], ["A", "C"]]
        )
        let stacked = Dictionary(uniqueKeysWithValues: graph.nodes.map {
            ($0.id, MapPoint(x: 0.5, y: 0.5))
        })
        let separated = graph.separated(stacked)
        let a = separated["a"]!
        let b = separated["b"]!
        let distance = ((a.x - b.x) * 1000 * (a.x - b.x) * 1000
            + (a.y - b.y) * 700 * (a.y - b.y) * 700).squareRoot()
        XCTAssertGreaterThanOrEqual(distance, 60)
    }

    func testSingleNodeSitsInTheCentre() {
        let graph = CategoryGraph(counts: [TagCount(name: "Only", count: 1)], videoTags: [], includeIsolated: true)
        XCTAssertEqual(graph.layout()["only"], MapPoint(x: 0.5, y: 0.5))
    }
}
