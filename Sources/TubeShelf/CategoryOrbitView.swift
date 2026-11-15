import SwiftUI
import AppKit
import SceneKit
import TubeShelfCore

/// Optional 3D orbit view. Same categories and links as the 2D map, with custom
/// camera controls: left-drag orbits, right-drag pans, scroll/pinch zooms.
struct CategoryOrbitView: View {
    let model: AppModel

    @State private var graph: CategoryGraph?
    @State private var points: [String: MapPoint] = [:]
    @State private var spins = false
    @State private var resetToken = 0
    @State private var appeared = false

    private var activeName: String? {
        if case .tag(let name) = model.filter { return name }
        return nil
    }

    var body: some View {
        ZStack {
            background
            if let graph, graph.nodes.isEmpty {
                emptyState(graph)
            } else if let graph {
                OrbitSceneView(
                    graph: graph,
                    points: points,
                    selectedName: activeName,
                    spins: spins,
                    resetToken: resetToken,
                    onSelect: { name in model.select(.tag(name)) }
                )
                .opacity(appeared ? 1 : 0)

                infoCard(graph)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)

                controls(graph)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
        .task { rebuildIfNeeded() }
        .onChange(of: model.library) { _, _ in rebuild() }
        .onChange(of: model.playlists) { _, _ in rebuild() }
    }

    private var background: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [Theme.violet.opacity(0.10), .clear],
                center: .init(x: 0.62, y: 0.38),
                startRadius: 20,
                endRadius: 620
            )
        }
        .ignoresSafeArea()
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

    @ViewBuilder
    private func infoCard(_ graph: CategoryGraph) -> some View {
        if let name = activeName,
           let node = graph.nodes.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            VStack(alignment: .leading, spacing: 3) {
                Text(node.name)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(node.count) video\(node.count == 1 ? "" : "s") · \(CategoryGraph.groupKey(node.name))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08))
            )
        }
    }

    private func controls(_ graph: CategoryGraph) -> some View {
        HStack(spacing: 12) {
            Text("Left-drag orbits · right-drag pans · scroll or pinch zooms")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            Button(spins ? "Pause spin" : "Spin") { spins.toggle() }
                .buttonStyle(.link)
                .font(.system(size: 10))
            Button("Reset view") { resetToken += 1 }
                .buttonStyle(.link)
                .font(.system(size: 10))
            Spacer()
            Text("\(graph.nodes.count) categories · \(graph.hiddenCount) unlinked hidden")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
            if activeName != nil {
                Button("Show videos") { model.presentation = .grid }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
    }

    @ViewBuilder
    private func emptyState(_ graph: CategoryGraph) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing to orbit yet")
                .font(.system(size: 13, weight: .semibold))
            Text("The 3D view needs categories that share a video. Add a second category to connect these \(graph.hiddenCount) categories.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SceneKit bridge

struct OrbitSceneView: NSViewRepresentable {
    let graph: CategoryGraph
    let points: [String: MapPoint]
    let selectedName: String?
    let spins: Bool
    let resetToken: Int
    let onSelect: (String) -> Void

    func makeNSView(context: Context) -> OrbitSCNView {
        let view = OrbitSCNView()
        context.coordinator.onSelect = onSelect
        context.coordinator.configure(view)
        return view
    }

    func updateNSView(_ view: OrbitSCNView, context: Context) {
        context.coordinator.update(
            view: view,
            graph: graph,
            points: points,
            selectedName: selectedName,
            spins: spins,
            resetToken: resetToken
        )
    }

    static func dismantleNSView(_ view: OrbitSCNView, coordinator: Coordinator) {
        coordinator.stopSpin()
        view.scene = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onSelect: ((String) -> Void)?

        private let scene = SCNScene()
        private let content = SCNNode()
        private let pivot = SCNNode()
        private let cameraNode = SCNNode()
        private weak var view: OrbitSCNView?

        private var lastGraph: CategoryGraph?
        private var nodeNodes: [String: SCNNode] = [:]
        private var baseColours: [String: NSColor] = [:]
        private var nodeNames: Set<String> = []
        private var selectedName: String?
        private var spins = false
        private var spinTimer: Timer?
        private var lastResetToken = 0

        private var azimuth: Double = 0.65
        private var elevation: Double = 0.32
        private var distance: Double = 14
        private var target = SCNVector3Zero
        private var startAzimuth: Double = 0
        private var startElevation: Double = 0
        private var startDistance: Double = 14
        private var startTarget = SCNVector3Zero

        func configure(_ view: OrbitSCNView) {
            self.view = view
            view.scene = scene
            view.allowsCameraControl = false
            view.backgroundColor = NSColor(calibratedRed: 0.045, green: 0.05, blue: 0.075, alpha: 1)
            view.antialiasingMode = .multisampling4X
            view.rendersContinuously = true
            view.autoenablesDefaultLighting = false
            view.onScroll = { [weak self] delta in
                self?.zoom(by: delta)
            }

            scene.rootNode.addChildNode(content)
            scene.rootNode.addChildNode(pivot)

            let camera = SCNCamera()
            camera.fieldOfView = 46
            camera.zNear = 0.1
            camera.zFar = 200
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(0, 0, CGFloat(distance))
            pivot.addChildNode(cameraNode)

            let ambient = SCNLight()
            ambient.type = .ambient
            ambient.intensity = 420
            ambient.color = NSColor.white
            let ambientNode = SCNNode()
            ambientNode.light = ambient
            scene.rootNode.addChildNode(ambientNode)

            let key = SCNLight()
            key.type = .omni
            key.intensity = 900
            key.color = NSColor(calibratedRed: 0.75, green: 0.7, blue: 1, alpha: 1)
            let keyNode = SCNNode()
            keyNode.light = key
            keyNode.position = SCNVector3(5, 7, 9)
            scene.rootNode.addChildNode(keyNode)

            let orbit = NSPanGestureRecognizer(target: self, action: #selector(handleOrbit(_:)))
            orbit.buttonMask = 0x1
            view.addGestureRecognizer(orbit)

            let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.buttonMask = 0x2
            view.addGestureRecognizer(pan)

            let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnify(_:)))
            view.addGestureRecognizer(magnify)

            let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            view.addGestureRecognizer(click)

            applyCamera()
        }

        func update(
            view: OrbitSCNView,
            graph: CategoryGraph,
            points: [String: MapPoint],
            selectedName: String?,
            spins: Bool,
            resetToken: Int
        ) {
            self.view = view
            if lastGraph != graph {
                build(graph, points: points)
                lastGraph = graph
            }
            if self.spins != spins {
                self.spins = spins
                if spins { startSpin() } else { stopSpin() }
            }
            if resetToken != lastResetToken {
                lastResetToken = resetToken
                resetCamera()
            }
            if self.selectedName != selectedName {
                self.selectedName = selectedName
                updateSelection()
            }
            applyCamera()
        }

        // MARK: Build

        private func build(_ graph: CategoryGraph, points: [String: MapPoint]) {
            content.childNodes.forEach { $0.removeFromParentNode() }
            nodeNodes.removeAll()
            baseColours.removeAll()
            nodeNames = []

            let groups = Set(graph.nodes.map { CategoryGraph.groupKey($0.name) }).sorted()
            var depth: [String: Double] = [:]
            for (index, group) in groups.enumerated() {
                let fraction = groups.count > 1
                    ? Double(index) / Double(groups.count - 1) - 0.5
                    : 0
                depth[group] = fraction * 4.2
            }

            let palette = [
                NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.90, green: 0.28, blue: 0.30, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.55, blue: 0.95, alpha: 1),
                NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.70, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.72, blue: 0.40, alpha: 1),
                NSColor(calibratedRed: 0.90, green: 0.55, blue: 0.25, alpha: 1),
                NSColor(calibratedRed: 0.90, green: 0.40, blue: 0.65, alpha: 1)
            ]
            func colour(for name: String) -> NSColor {
                let key = CategoryGraph.groupKey(name)
                let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
                return palette[sum % palette.count]
            }

            var positions: [String: SCNVector3] = [:]
            for node in graph.nodes {
                guard let point = points[node.id] else { continue }
                let position = SCNVector3(
                    CGFloat((point.x - 0.5) * 9),
                    CGFloat((0.5 - point.y) * 7),
                    CGFloat(depth[CategoryGraph.groupKey(node.name)] ?? 0)
                )
                positions[node.id] = position
                nodeNames.insert(node.name)

                let radius = 0.08 + (node.radius / 30) * 0.30
                let sphere = SCNSphere(radius: radius)
                let material = SCNMaterial()
                material.diffuse.contents = colour(for: node.name)
                material.emission.contents = colour(for: node.name)
                material.emission.intensity = 0.55
                material.roughness.contents = 0.35
                material.metalness.contents = 0.15
                sphere.materials = [material]

                let sphereNode = SCNNode(geometry: sphere)
                sphereNode.name = node.name
                sphereNode.position = position
                content.addChildNode(sphereNode)
                nodeNodes[node.name] = sphereNode
                baseColours[node.name] = colour(for: node.name)

                let halo = SCNSphere(radius: radius * 1.42)
                let haloMaterial = SCNMaterial()
                haloMaterial.diffuse.contents = colour(for: node.name)
                haloMaterial.emission.contents = colour(for: node.name)
                haloMaterial.emission.intensity = 0.35
                haloMaterial.transparency = 0.16
                haloMaterial.lightingModel = .constant
                haloMaterial.blendMode = .add
                halo.materials = [haloMaterial]
                let haloNode = SCNNode(geometry: halo)
                haloNode.position = position
                content.addChildNode(haloNode)
            }

            let edgeMaterial = SCNMaterial()
            edgeMaterial.diffuse.contents = NSColor(calibratedWhite: 0.72, alpha: 1)
            edgeMaterial.emission.contents = NSColor(calibratedWhite: 0.55, alpha: 1)
            edgeMaterial.emission.intensity = 0.55
            edgeMaterial.transparency = 0.72
            edgeMaterial.lightingModel = .constant

            for edge in graph.edges {
                guard let a = positions[edge.a], let b = positions[edge.b] else { continue }
                let dx = b.x - a.x
                let dy = b.y - a.y
                let dz = b.z - a.z
                let length = (dx * dx + dy * dy + dz * dz).squareRoot()
                guard length > 0.01 else { continue }

                let cylinder = SCNCylinder(
                    radius: 0.022 + min(0.020, Double(edge.shared) * 0.003),
                    height: CGFloat(length)
                )
                cylinder.radialSegmentCount = 8
                cylinder.materials = [edgeMaterial]
                let edgeNode = SCNNode(geometry: cylinder)
                edgeNode.position = SCNVector3(
                    (a.x + b.x) / 2,
                    (a.y + b.y) / 2,
                    (a.z + b.z) / 2
                )
                edgeNode.look(at: b, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
                content.addChildNode(edgeNode)
            }

            // A handful of billboard labels keeps 3D legible without a text wall.
            let labelled = graph.nodes.sorted { $0.count > $1.count }.prefix(8)
            for node in labelled {
                guard let position = positions[node.id] else { continue }
                let text = SCNText(string: node.name, extrusionDepth: 0)
                text.font = NSFont.systemFont(ofSize: 0.22, weight: .medium)
                text.flatness = 0.3
                let material = SCNMaterial()
                material.diffuse.contents = NSColor.white
                material.emission.contents = NSColor.white
                material.emission.intensity = 0.8
                material.lightingModel = .constant
                text.materials = [material]
                let textNode = SCNNode(geometry: text)
                textNode.scale = SCNVector3(1.0, 1.0, 1.0)
                textNode.position = SCNVector3(
                    position.x,
                    position.y + 0.34,
                    position.z
                )
                let billboard = SCNBillboardConstraint()
                billboard.freeAxes = .Y
                textNode.constraints = [billboard]
                content.addChildNode(textNode)
            }

            updateSelection()
            applyCamera()
            debugSnapshotIfRequested()
        }

        // MARK: Camera

        private func applyCamera() {
            pivot.position = target
            pivot.eulerAngles = SCNVector3(CGFloat(elevation), CGFloat(azimuth), 0)
            cameraNode.position = SCNVector3(0, 0, CGFloat(distance))
        }

        private func resetCamera() {
            azimuth = 0.65
            elevation = 0.32
            distance = 14
            target = SCNVector3Zero
            applyCamera()
        }

        private func zoom(by delta: CGFloat) {
            distance = min(26, max(5, distance * exp(-Double(delta) * 0.02)))
            applyCamera()
        }

        @objc private func handleOrbit(_ gesture: NSPanGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .began:
                startAzimuth = azimuth
                startElevation = elevation
            case .changed:
                let translation = gesture.translation(in: view)
                azimuth = startAzimuth - Double(translation.x) * 0.008
                elevation = min(1.15, max(-1.15, startElevation + Double(translation.y) * 0.008))
                applyCamera()
            default:
                break
            }
        }

        @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .began:
                startTarget = target
            case .changed:
                let translation = gesture.translation(in: view)
                let scale = CGFloat(distance * 0.0018)
                let right = SCNVector3(CGFloat(cos(azimuth)), 0, CGFloat(-sin(azimuth)))
                let dx = translation.x * scale
                let dy = translation.y * scale
                let nextX = startTarget.x - right.x * dx
                let nextY = startTarget.y + dy
                let nextZ = startTarget.z - right.z * dx
                target = SCNVector3(nextX, nextY, nextZ)
                applyCamera()
            default:
                break
            }
        }

        @objc private func handleMagnify(_ gesture: NSMagnificationGestureRecognizer) {
            if gesture.state == .began {
                startDistance = distance
            } else if gesture.state == .changed {
                distance = min(26, max(5, startDistance / (1 + Double(gesture.magnification))))
                applyCamera()
            }
        }

        @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            guard let hit = view.hitTest(point, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue]).first
            else { return }
            var node: SCNNode? = hit.node
            while let current = node {
                if let name = current.name, nodeNames.contains(name) {
                    onSelect?(name)
                    return
                }
                node = current.parent
            }
        }

        private func updateSelection() {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.18
            let accent = NSColor(calibratedRed: 0.90, green: 0.28, blue: 0.30, alpha: 1)
            for (name, node) in nodeNodes {
                let isSelected = name.caseInsensitiveCompare(selectedName ?? "") == .orderedSame
                let base = baseColours[name] ?? NSColor.white
                node.scale = isSelected ? SCNVector3(1.55, 1.55, 1.55) : SCNVector3(1, 1, 1)
                node.geometry?.firstMaterial?.diffuse.contents = isSelected ? accent : base
                node.geometry?.firstMaterial?.emission.contents = isSelected ? accent : base
                node.geometry?.firstMaterial?.emission.intensity = isSelected ? 2.1 : 0.55
            }
            SCNTransaction.commit()
        }

        // MARK: Spin

        func startSpin() {
            guard spinTimer == nil else { return }
            let timer = Timer(
                timeInterval: 1.0 / 40.0,
                target: self,
                selector: #selector(tick),
                userInfo: nil,
                repeats: true
            )
            RunLoop.main.add(timer, forMode: .common)
            spinTimer = timer
        }

        func stopSpin() {
            spinTimer?.invalidate()
            spinTimer = nil
        }

        @objc private func tick() {
            guard spins else { return }
            azimuth += 0.0035
            applyCamera()
        }

        // MARK: Debug capture

        private func debugSnapshotIfRequested() {
            #if DEBUG
            guard let path = ProcessInfo.processInfo.environment["TUBESHELF_ORBIT_SNAPSHOT"],
                  !path.isEmpty
            else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
                guard let view = self?.view else { return }
                let image = view.snapshot()
                guard let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:])
                else { return }
                try? png.write(to: URL(fileURLWithPath: path))
            }
            #endif
        }
    }
}

/// Scroll-wheel zoom; SceneKit's own camera control is disabled so clicks can
/// still select a category.
final class OrbitSCNView: SCNView {
    var onScroll: ((CGFloat) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        onScroll?(event.scrollingDeltaY)
    }

    override var acceptsFirstResponder: Bool { true }
}
