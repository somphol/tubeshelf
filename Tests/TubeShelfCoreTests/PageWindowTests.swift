import XCTest
@testable import TubeShelfCore

final class PageWindowTests: XCTestCase {
    func testEmptyShelfHasOneEmptyPage() {
        let window = PageWindow(total: 0, pageSize: 48, pageIndex: 0)
        XCTAssertEqual(window.pageCount, 1)
        XCTAssertEqual(window.rangeLabel, "0 videos")
        XCTAssertTrue(window.isFirst)
        XCTAssertTrue(window.isLast)
        XCTAssertFalse(window.hasMultiplePages)
        XCTAssertTrue(window.slice([Int]()).isEmpty)
    }

    func testExactMultipleHasNoHalfPage() {
        let window = PageWindow(total: 96, pageSize: 48, pageIndex: 1)
        XCTAssertEqual(window.pageCount, 2)
        XCTAssertEqual(window.startIndex, 48)
        XCTAssertEqual(window.endIndex, 96)
        XCTAssertEqual(window.rangeLabel, "49–96 of 96")
        XCTAssertTrue(window.isLast)
    }

    func testPartialLastPage() {
        let window = PageWindow(total: 100, pageSize: 48, pageIndex: 2)
        XCTAssertEqual(window.pageCount, 3)
        XCTAssertEqual(window.startIndex, 96)
        XCTAssertEqual(window.endIndex, 100)
        XCTAssertEqual(window.rangeLabel, "97–100 of 100")
        XCTAssertTrue(window.isLast)
        XCTAssertFalse(window.isFirst)
    }

    func testRequestedPageIsClampedWhenTheShelfShrinks() {
        let shrunk = PageWindow(total: 10, pageSize: 48, pageIndex: 7)
        XCTAssertEqual(shrunk.pageIndex, 0)
        XCTAssertEqual(shrunk.pageCount, 1)
        XCTAssertEqual(shrunk.rangeLabel, "1–10 of 10")

        let emptied = PageWindow(total: 0, pageSize: 48, pageIndex: 3)
        XCTAssertEqual(emptied.pageIndex, 0)
        XCTAssertEqual(emptied.startIndex, 0)
    }

    func testSliceMatchesBoundsAndNeverOverrunsSource() {
        let items = Array(0..<250)
        let window = PageWindow(total: items.count, pageSize: 100, pageIndex: 2)
        XCTAssertEqual(Array(window.slice(items)), Array(200..<250))

        // Source shorter than the reported total (mid-deletion render).
        let stale = PageWindow(total: 300, pageSize: 100, pageIndex: 2)
        XCTAssertEqual(Array(stale.slice(Array(0..<210))), Array(200..<210))
    }

    func testNavigationHelpers() {
        let window = PageWindow(total: 500, pageSize: 50, pageIndex: 4)
        XCTAssertEqual(window.page(0).rangeLabel, "1–50 of 500")
        XCTAssertEqual(window.page(99).pageIndex, 9, "page index is clamped to the last page")
        XCTAssertEqual(window.page(99).rangeLabel, "451–500 of 500")
    }

    func testTinyPageSizeDoesNotProduceZeroPages() {
        let window = PageWindow(total: 5, pageSize: 1, pageIndex: 2)
        XCTAssertEqual(window.pageCount, 5)
        XCTAssertEqual(window.rangeLabel, "3–3 of 5")
        XCTAssertEqual(PageWindow(total: 5, pageSize: 0, pageIndex: 0).pageSize, 1)
    }
}
