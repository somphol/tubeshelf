import Foundation

/// Pure pagination maths. The caller keeps the requested page; this clamps it
/// against the current total so a shrinking shelf can never strand the view on
/// an empty page.
public struct PageWindow: Equatable, Sendable {
    public let total: Int
    public let pageSize: Int
    public let pageIndex: Int
    public let pageCount: Int

    public init(total: Int, pageSize: Int, pageIndex: Int) {
        let safeTotal = max(0, total)
        let safeSize = max(1, pageSize)
        let count = max(1, Int((Double(safeTotal) / Double(safeSize)).rounded(.up)))
        self.total = safeTotal
        self.pageSize = safeSize
        self.pageCount = count
        self.pageIndex = min(max(0, pageIndex), count - 1)
    }

    public var isFirst: Bool { pageIndex == 0 }
    public var isLast: Bool { pageIndex >= pageCount - 1 }
    public var hasMultiplePages: Bool { pageCount > 1 }

    /// Zero-based, half-open bounds of the current page.
    public var startIndex: Int { min(total, pageIndex * pageSize) }
    public var endIndex: Int { min(total, startIndex + pageSize) }

    /// Human label, 1-based and inclusive: "49–96 of 312".
    public var rangeLabel: String {
        guard total > 0 else { return "0 videos" }
        return "\(startIndex + 1)–\(endIndex) of \(total)"
    }

    public var pageLabel: String { "Page \(pageIndex + 1) of \(pageCount)" }

    public func slice<T>(_ items: [T]) -> ArraySlice<T> {
        let upper = min(items.count, endIndex)
        let lower = min(startIndex, upper)
        return items[lower..<upper]
    }

    public func page(_ index: Int) -> PageWindow {
        PageWindow(total: total, pageSize: pageSize, pageIndex: index)
    }
}
