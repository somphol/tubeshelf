import SwiftUI
import AppKit
import TubeShelfCore

/// The optional category map: nodes are categories, area is video count, edges
/// are shared videos. It presents the same filter as the grid and never mutates
/// the library.
struct CategoryMapView: View {
    let model: AppModel

    @State private var graph: CategoryGraph?
    @State private var points: [String: MapPoint] = [:]
    @State private var hoveredID: String?
    @State private var lastTap: (id: String, time: Date)?
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastZoom: CGFloat = 1
    @State private var lastPan: CGSize = .zero
    @State private var appeared = false

    private let padding: CGFloat = 38

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let graph, graph.nodes.isEmpty {
                    emptyState(graph)
                } else if let graph {
                    canvas(graph, size: geometry.size)
                        .opacity(appeared ? 1 : 0)
                        .scaleEffect(appeared ? 1 : 0.985)
                    infoCard(graph)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .allowsHitTesting(false)
                    legend(graph)
                        .padding(16)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
            .task { rebuildIfNeeded() }
            .onChange(of: model.library) { _, _ in rebuild() }
            .onChange(of: model.playlists) { _, _ in rebuild() }
        }
    }

    private var activeID: String? {
        if case .tag(let name) = model.filter { return name.lowercased() }
        return nil
    }

    private func rebuildIfNeeded() {
        if graph == nil { rebuild() }
    }

    private func rebuild() {
        let graph = CategoryGraph(
            counts: model.combinedTagCounts,
            videoTags: model.library.videos.map(\.tags)
        )
        self.graph = graph
        self.points = graph.separated(graph.layout())
    }

    // MARK: - Canvas

    private func canvas(_ graph: CategoryGraph, size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let active = activeID
            let focus = hoveredID ?? active
            let neighbours: Set<String> = {
                guard let focus else { return [] }
                var result: Set<String> = [focus]
                for edge in graph.edges where edge.a == focus || edge.b == focus {
                    result.insert(edge.a)
                    result.insert(edge.b)
                }
                return result
            }()

            // A warm vignette behind the graph; no assets involved.
            context.fill(
                Path(CGRect(origin: .zero, size: canvasSize)),
                with: .radialGradient(
                    Gradient(colors: [Theme.violet.opacity(0.07), .clear]),
                    center: CGPoint(x: canvasSize.width * 0.62, y: canvasSize.height * 0.38),
                    startRadius: 10,
                    endRadius: max(canvasSize.width, canvasSize.height) * 0.72
                )
            )

            context.translateBy(
                x: canvasSize.width / 2 + pan.width,
                y: canvasSize.height / 2 + pan.height
            )
            context.scaleBy(x: zoom, y: zoom)
            context.translateBy(x: -canvasSize.width / 2, y: -canvasSize.height / 2)

            for edge in graph.edges {
                guard let a = position(edge.a, in: canvasSize),
                      let b = position(edge.b, in: canvasSize)
                else { continue }
                let touchesFocus = focus == edge.a || focus == edge.b
                let dimmed = focus != nil && !touchesFocus
                let width = 0.7 + min(2.4, Double(edge.shared) * 0.45)

                var path = Path()
                path.move(to: a)
                let dx = b.x - a.x
                let dy = b.y - a.y
                let distance = max(1, (dx * dx + dy * dy).squareRoot())
                let bend = min(26, distance * 0.12) * bendSign(edge.id)
                path.addQuadCurve(
                    to: b,
                    control: CGPoint(
                        x: (a.x + b.x) / 2 - dy / distance * bend,
                        y: (a.y + b.y) / 2 + dx / distance * bend
                    )
                )

                let colour = touchesFocus ? Theme.accent : Color.secondary
                let opacity = dimmed ? 0.05 : (touchesFocus ? 0.75 : 0.26)
                // A wide translucent pass reads as a glow without a blur filter.
                if !dimmed {
                    context.stroke(
                        path,
                        with: .color(colour.opacity(touchesFocus ? 0.16 : 0.05)),
                        lineWidth: width + 4
                    )
                }
                context.stroke(path, with: .color(colour.opacity(opacity)), lineWidth: width)
            }

            let labelled = Set(
                graph.nodes.sorted { $0.count > $1.count }.prefix(8).map(\.id)
            )

            for node in graph.nodes {
                guard let center = position(node.id, in: canvasSize) else { continue }
                let isActive = node.id == active
                let isHovered = node.id == hoveredID
                let isNeighbour = neighbours.contains(node.id)
                let dimmed = focus != nil && !isNeighbour
                let colour = groupColor(node.name)
                let rect = CGRect(
                    x: center.x - node.radius,
                    y: center.y - node.radius,
                    width: node.radius * 2,
                    height: node.radius * 2
                )

                if !dimmed {
                    let halo = rect.insetBy(dx: -4, dy: -4)
                    context.fill(
                        Path(ellipseIn: halo),
                        with: .color((isActive || isHovered ? Theme.accent : colour).opacity(0.08))
                    )
                }
                context.fill(
                    Path(ellipseIn: rect),
                    with: .linearGradient(
                        Gradient(colors: isActive || isHovered
                            ? [Theme.accent.opacity(0.55), Theme.accent.opacity(0.18)]
                            : [colour.opacity(dimmed ? 0.08 : 0.36), colour.opacity(dimmed ? 0.04 : 0.12)]),
                        startPoint: CGPoint(x: rect.minX, y: rect.minY),
                        endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                )
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(
                        isActive ? Theme.accent
                            : colour.opacity(dimmed ? 0.18 : (isHovered ? 0.95 : 0.62))
                    ),
                    lineWidth: isActive ? 2 : 1
                )
            }

            // Labels after every circle; a pill keeps them legible over edges.
            var occupied: [CGRect] = []
            let labelNodes = graph.nodes
                .filter {
                    $0.id == hoveredID || $0.id == active
                        || (focus == nil && labelled.contains($0.id))
                        || neighbours.contains($0.id)
                }
                .sorted { $0.count > $1.count }
            for node in labelNodes {
                guard let center = position(node.id, in: canvasSize) else { continue }
                let isActive = node.id == active
                let isHovered = node.id == hoveredID
                let text = Text(node.name)
                    .font(.system(size: 10, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? Theme.accent : .secondary)
                let resolved = context.resolve(text)
                let measured = resolved.measure(in: CGSize(width: 200, height: 24))
                let rect = CGRect(
                    x: center.x - measured.width / 2,
                    y: center.y + node.radius + 6,
                    width: measured.width,
                    height: measured.height
                )
                let collides = occupied.contains {
                    $0.intersects(rect.insetBy(dx: -3, dy: -1))
                }
                if collides && !isActive && !isHovered { continue }
                let pill = rect.insetBy(dx: -4, dy: -2)
                occupied.append(pill)
                context.fill(
                    Path(roundedRect: pill, cornerRadius: 4),
                    with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.82))
                )
                context.draw(resolved, at: CGPoint(x: center.x, y: rect.minY), anchor: .top)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoveredID = node(at: mapPoint(location, in: size), in: graph, size: size)?.id
            case .ended:
                hoveredID = nil
            }
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                let location = mapPoint(value.location, in: size)
                guard let node = node(at: location, in: graph, size: size) else {
                    lastTap = nil
                    return
                }
                let now = Date()
                let isDouble = lastTap.map {
                    $0.id == node.id && now.timeIntervalSince($0.time) < 0.4
                } ?? false
                model.select(.tag(node.name))
                if isDouble {
                    lastTap = nil
                    model.presentation = .grid
                } else {
                    lastTap = (node.id, now)
                }
            }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    zoom = min(2.6, max(0.55, lastZoom * value))
                }
                .onEnded { _ in lastZoom = zoom }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let limit = max(size.width, size.height) * 0.6
                    pan = CGSize(
                        width: min(limit, max(-limit, lastPan.width + value.translation.width)),
                        height: min(limit, max(-limit, lastPan.height + value.translation.height))
                    )
                }
                .onEnded { _ in lastPan = pan }
        )
        .contextMenu {
            if let node = hoveredNode(in: graph) {
                Button(model.library.isPinned(node.name) ? "Unpin category" : "Pin category") {
                    model.togglePin(node.name)
                }
                Button("Present this category") {
                    model.openDeckForTag(node.name)
                }
                Button("Show videos") {
                    model.presentation = .grid
                }
            } else {
                Text("Hover a category")
            }
        }
        .accessibilityLabel("Category map")
        .accessibilityValue(graph.mapSummary)
        .accessibilityRepresentation {
            List(graph.nodes) { node in
                Button("\(node.name), \(node.count) videos") {
                    model.select(.tag(node.name))
                }
            }
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private func infoCard(_ graph: CategoryGraph) -> some View {
        let node = hoveredNode(in: graph) ?? graph.nodes.first { $0.id == activeID }
        if let node {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(node.count) video\(node.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                if let partner = strongestPartner(of: node, in: graph) {
                    Text("Shares most with \(partner.name) · \(partner.shared)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
    }

    private func legend(_ graph: CategoryGraph) -> some View {
        HStack(spacing: 10) {
            Text(legendText(graph))
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            if zoom != 1 || pan != .zero {
                Button("Reset view") {
                    withAnimation(.easeOut(duration: 0.25)) {
                        zoom = 1
                        lastZoom = 1
                        pan = .zero
                        lastPan = .zero
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 10))
            }
            if activeID != nil {
                Button("Show videos") { model.presentation = .grid }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
    }

    private func legendText(_ graph: CategoryGraph) -> String {
        var text = "\(graph.nodes.count) categories · size = videos · colour = group · line = shared videos"
        if graph.hiddenCount > 0 {
            text += " · \(graph.hiddenCount) unlinked hidden"
        }
        return text
    }

    @ViewBuilder
    private func emptyState(_ graph: CategoryGraph) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No shared categories yet")
                .font(.system(size: 13, weight: .semibold))
            Text("The map draws a line when one video carries two categories. Add a second category to connect these \(graph.hiddenCount) categories.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func strongestPartner(
        of node: CategoryGraph.Node,
        in graph: CategoryGraph
    ) -> (name: String, shared: Int)? {
        guard let edge = graph.edges
            .filter({ $0.a == node.id || $0.b == node.id })
            .max(by: { $0.shared < $1.shared })
        else { return nil }
        let otherID = edge.a == node.id ? edge.b : edge.a
        guard let other = graph.nodes.first(where: { $0.id == otherID }) else { return nil }
        return (other.name, edge.shared)
    }

    // MARK: - Geometry

    private func position(_ id: String, in size: CGSize) -> CGPoint? {
        guard let point = points[id] else { return nil }
        let width = max(1, size.width - padding * 2)
        let height = max(1, size.height - padding * 2)
        return CGPoint(
            x: padding + CGFloat(point.x) * width,
            y: padding + CGFloat(point.y) * height
        )
    }

    /// Undo zoom/pan for hit-testing and hover.
    private func mapPoint(_ location: CGPoint, in size: CGSize) -> CGPoint {
        let centre = CGPoint(
            x: size.width / 2 + pan.width,
            y: size.height / 2 + pan.height
        )
        return CGPoint(
            x: (location.x - centre.x) / zoom + size.width / 2,
            y: (location.y - centre.y) / zoom + size.height / 2
        )
    }

    /// Colour carries the category group, not an arbitrary per-node hue.
    private func groupColor(_ name: String) -> Color {
        let group = CategoryGraph.groupKey(name)
        let palette: [Color] = [Theme.violet, Theme.accent, .blue, .teal, .green, .orange, .pink]
        let sum = group.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return palette[sum % palette.count]
    }

    private func bendSign(_ id: String) -> CGFloat {
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return sum.isMultiple(of: 2) ? 1 : -1
    }

    private func node(
        at location: CGPoint,
        in graph: CategoryGraph,
        size: CGSize
    ) -> CategoryGraph.Node? {
        graph.nodes
            .compactMap { node -> (CategoryGraph.Node, CGFloat)? in
                guard let center = position(node.id, in: size) else { return nil }
                let distance = hypot(location.x - center.x, location.y - center.y)
                let hitRadius = max(node.radius + 5, 13)
                return distance <= hitRadius ? (node, distance) : nil
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func hoveredNode(in graph: CategoryGraph) -> CategoryGraph.Node? {
        guard let hoveredID else { return nil }
        return graph.nodes.first { $0.id == hoveredID }
    }
}

private extension CategoryGraph {
    var mapSummary: String {
        "\(nodes.count) categories, \(edges.count) shared-video links"
    }
}
