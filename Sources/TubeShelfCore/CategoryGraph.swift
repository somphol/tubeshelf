import Foundation

/// A point in a normalised 0…1 map space, independent of any UI framework.
public struct MapPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// Categories as nodes and shared videos as edges. Pure: no SwiftUI, no view
/// sizes. The view scales the normalised layout to its own bounds.
public struct CategoryGraph: Equatable, Sendable {
    public struct Node: Identifiable, Equatable, Sendable {
        /// Lowercased category name; stable across launches.
        public let id: String
        /// The spelling shown in the sidebar.
        public let name: String
        public let count: Int
        /// Suggested radius in points; the view uses it directly.
        public let radius: Double
    }

    public struct Edge: Identifiable, Equatable, Sendable {
        public let a: String
        public let b: String
        public let shared: Int

        public var id: String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }
    }

    public let nodes: [Node]
    public let edges: [Edge]
    public let maxCount: Int
    /// Categories with no remaining link. They are drawn only on request.
    public let hiddenCount: Int

    /// - Parameters:
    ///   - counts: sidebar counts (videos + courses).
    ///   - videoTags: each video's categories, used to weigh shared membership.
    ///   - maxEdgesPerNode: keeps the busiest categories from becoming a hairball.
    ///   - includeIsolated: keep categories with no links (they ring the layout).
    public init(
        counts: [TagCount],
        videoTags: [[String]],
        maxEdgesPerNode: Int = 4,
        includeIsolated: Bool = false
    ) {
        var seen = Set<String>()
        var built: [Node] = []
        for tag in counts {
            let key = tag.name.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            built.append(Node(id: key, name: tag.name, count: tag.count, radius: 0))
        }

        let maxCount = built.map(\.count).max() ?? 1
        let largest = Double(max(1, maxCount))
        built = built.map { node in
            // Area grows with the count; the floor keeps tiny nodes clickable.
            let radius = max(5.5, 30 * (Double(node.count) / largest).squareRoot())
            return Node(id: node.id, name: node.name, count: node.count, radius: radius)
        }
        built.sort { $0.id < $1.id }

        let known = Set(built.map(\.id))
        var tally: [String: Int] = [:]
        for tags in videoTags {
            var unique = Set<String>()
            for tag in tags {
                let key = tag.lowercased()
                if known.contains(key) { unique.insert(key) }
            }
            let keys = unique.sorted()
            guard keys.count > 1 else { continue }
            for i in 0..<(keys.count - 1) {
                for j in (i + 1)..<keys.count {
                    tally["\(keys[i])|\(keys[j])", default: 0] += 1
                }
            }
        }

        // A single shared video is signal in a small shelf and noise in a big one.
        let minShared = tally.count > max(20, built.count * 3) ? 2 : 1
        var candidates = tally
            .filter { $0.value >= minShared }
            .map { (pair, shared) -> Edge in
                let parts = pair.split(separator: "|", maxSplits: 1).map(String.init)
                return Edge(a: parts[0], b: parts[1], shared: shared)
            }

        // Greedy degree cap, strongest first: a hub cannot accumulate every
        // one-video link, and ties stay deterministic.
        candidates.sort(by: Self.strongestFirst)
        var degrees: [String: Int] = [:]
        var capped: [Edge] = []
        for edge in candidates {
            guard degrees[edge.a, default: 0] < max(1, maxEdgesPerNode),
                  degrees[edge.b, default: 0] < max(1, maxEdgesPerNode)
            else { continue }
            capped.append(edge)
            degrees[edge.a, default: 0] += 1
            degrees[edge.b, default: 0] += 1
        }
        candidates = capped

        let linked = Set(candidates.flatMap { [$0.a, $0.b] })
        let hidden = built.filter { !linked.contains($0.id) }
        self.nodes = includeIsolated ? built : built.filter { linked.contains($0.id) }
        self.edges = candidates
        self.maxCount = maxCount
        self.hiddenCount = hidden.count
    }

    private static func strongestFirst(_ lhs: Edge, _ rhs: Edge) -> Bool {
        lhs.shared == rhs.shared ? lhs.id < rhs.id : lhs.shared > rhs.shared
    }

    private func splitMix(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A deterministic, seeded force layout. Two calls on the same graph return
    /// identical points, so nodes do not jump between launches.
    public func layout(iterations: Int = 220) -> [String: MapPoint] {
        guard nodes.count > 1 else {
            return Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, MapPoint(x: 0.5, y: 0.5)) })
        }

        let ordered = nodes.sorted { $0.id < $1.id }
        let n = Double(ordered.count)
        let k = 0.46 / n.squareRoot()
        var points: [String: MapPoint] = [:]

        // Deterministic pseudo-random seeds. A spiral keeps its ring shape under
        // weak forces; scattered seeds let the clusters form instead.
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for node in ordered {
            let x = splitMix(&seed)
            let y = splitMix(&seed)
            points[node.id] = MapPoint(
                x: 0.16 + Double(x % 10_000) / 10_000 * 0.68,
                y: 0.16 + Double(y % 10_000) / 10_000 * 0.68
            )
        }

        let index = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0) })
        let repulsionK = k * k
        let attractionK = 1 / k

        for iteration in 0..<max(1, iterations) {
            var displacement = [MapPoint](repeating: MapPoint(x: 0, y: 0), count: ordered.count)

            for i in 0..<ordered.count {
                for j in (i + 1)..<ordered.count {
                    let a = points[ordered[i].id]!
                    let b = points[ordered[j].id]!
                    var dx = a.x - b.x
                    var dy = a.y - b.y
                    var distance = (dx * dx + dy * dy).squareRoot()
                    if distance < 0.001 {
                        // Perfectly overlapping seeds are nudged deterministically.
                        dx = 0.001 * (Double(i + 1))
                        dy = 0.001 * (Double(j + 1))
                        distance = (dx * dx + dy * dy).squareRoot()
                    }
                    let force = repulsionK / distance
                    let ux = dx / distance
                    let uy = dy / distance
                    displacement[i].x += ux * force
                    displacement[i].y += uy * force
                    displacement[j].x -= ux * force
                    displacement[j].y -= uy * force
                }
            }

            for edge in edges {
                guard let ia = index[edge.a], let ib = index[edge.b] else { continue }
                let a = points[edge.a]!
                let b = points[edge.b]!
                let dx = a.x - b.x
                let dy = a.y - b.y
                let distance = max(0.001, (dx * dx + dy * dy).squareRoot())
                // Stronger sharing pulls harder, but never more than 4×.
                let weight = min(4, Double(edge.shared))
                let force = (distance * distance) * attractionK * weight * 2.2
                let ux = dx / distance
                let uy = dy / distance
                displacement[ia].x -= ux * force
                displacement[ia].y -= uy * force
                displacement[ib].x += ux * force
                displacement[ib].y += uy * force
            }

            let temperature = 0.085 * (1 - Double(iteration) / Double(max(1, iterations))) + 0.002
            for (i, node) in ordered.enumerated() {
                displacement[i].x += (0.5 - points[node.id]!.x) * 0.22
                displacement[i].y += (0.5 - points[node.id]!.y) * 0.22
                let dx = displacement[i].x
                let dy = displacement[i].y
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 0 else { continue }
                let step = min(length, temperature)
                var point = points[node.id]!
                point.x = min(0.97, max(0.03, point.x + dx / length * step))
                point.y = min(0.97, max(0.03, point.y + dy / length * step))
                points[node.id] = point
            }
        }

        return points
    }

    /// Push overlapping circles apart in a virtual canvas. The force layout
    /// does not know node radii, so without this the largest nodes can sit on
    /// top of each other.
    public func separated(
        _ points: [String: MapPoint],
        width: Double = 1000,
        height: Double = 700,
        iterations: Int = 220
    ) -> [String: MapPoint] {
        guard nodes.count > 1 else { return points }
        var result = points
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })

        for _ in 0..<max(1, iterations) {
            var moved = false
            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    let a = nodes[i]
                    let b = nodes[j]
                    guard var pa = result[a.id], var pb = result[b.id] else { continue }
                    var dx = (pa.x - pb.x) * width
                    var dy = (pa.y - pb.y) * height
                    var distance = (dx * dx + dy * dy).squareRoot()
                    let minimum = a.radius + b.radius + 5
                    guard distance < minimum else { continue }
                    if distance < 0.001 {
                        dx = 0.001
                        dy = 0.001
                        distance = 0.001_414
                    }
                    let push = (minimum - distance) / 2
                    let ux = dx / distance
                    let uy = dy / distance
                    pa.x = min(0.97, max(0.03, pa.x + ux * push / width))
                    pa.y = min(0.97, max(0.03, pa.y + uy * push / height))
                    pb.x = min(0.97, max(0.03, pb.x - ux * push / width))
                    pb.y = min(0.97, max(0.03, pb.y - uy * push / height))
                    result[a.id] = pa
                    result[b.id] = pb
                    moved = true
                }
            }
            if !moved { break }
        }
        return result
    }
}
