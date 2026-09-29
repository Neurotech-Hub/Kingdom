import RealityKit
import simd
import UIKit

/// Owns one `AnimalInstance` per detected card and keeps each anchored in world space.
@MainActor
final class AnimalAnchorManager {
    var onInstancesChanged: (([AnimalInstanceSummary]) -> Void)?

    /// Seconds without an observation before an instance is removed from the scene.
    var removeAfter: TimeInterval = 1.5
    /// Observations farther than this from the current pose are treated as a moved card.
    var snapDistance: Float = 0.04
    /// Orientation change (radians) that is treated as a moved card.
    var snapAngle: Float = .pi / 6

    var labelsVisible = true {
        didSet {
            for instance in instances.values {
                instance.anchor.findEntity(named: Self.labelName)?.isEnabled = labelsVisible
            }
        }
    }

    private let catalog: AnimalCatalog
    private let assetManager: AnimalAssetManager
    private weak var scene: RealityKit.Scene?
    private var instances: [Int: AnimalInstance] = [:]
    private var selectionRing: Entity?

    private static let labelName = "label"
    /// Models are normalized nose-along-+Z; the card's +Z points toward its bottom edge.
    /// Turning 180° makes animals face the top edge of the tag as the artwork reads upright.
    private static let presentationYaw = simd_quatf(angle: .pi, axis: [0, 1, 0])

    init(catalog: AnimalCatalog, assetManager: AnimalAssetManager) {
        self.catalog = catalog
        self.assetManager = assetManager
    }

    func attach(to scene: RealityKit.Scene) {
        self.scene = scene
    }

    // MARK: Observations

    func handle(_ observations: [MarkerObservation]) {
        var changed = false
        for observation in observations {
            guard let card = catalog.card(markerID: observation.markerID),
                  let animal = catalog.animal(id: card.animalID) else { continue }

            if let instance = instances[observation.markerID] {
                refine(instance, with: observation)
                if instance.trackingState != .tracking, instance.observationCount >= 3 {
                    instance.trackingState = .tracking
                    changed = true
                }
            } else {
                create(card: card, animal: animal, observation: observation)
                changed = true
            }
        }
        if changed { publish() }
    }

    /// Removes cards that have left the camera view; they are recreated when seen again.
    func updateTrackingStates(now: TimeInterval) {
        let expired = instances.filter { now - $0.value.lastSeen > removeAfter }
        guard !expired.isEmpty else { return }
        for (markerID, instance) in expired {
            if let ring = selectionRing, ring.parent === instance.anchor {
                selectionRing = nil
            }
            instance.anchor.removeFromParent()
            instances[markerID] = nil
        }
        publish()
    }

    func reset() {
        for instance in instances.values {
            instance.anchor.removeFromParent()
        }
        instances.removeAll()
        selectionRing = nil
        publish()
    }

    // MARK: Selection

    func instanceID(for entity: Entity) -> UUID? {
        var current: Entity? = entity
        while let node = current {
            if let instance = instances.values.first(where: { $0.anchor === node }) {
                return instance.id
            }
            current = node.parent
        }
        return nil
    }

    func setSelected(_ instanceID: UUID?) {
        selectionRing?.removeFromParent()
        selectionRing = nil
        guard let instanceID,
              let instance = instances.values.first(where: { $0.id == instanceID }) else { return }
        let ring = makeSelectionRing(for: instance)
        instance.anchor.addChild(ring)
        selectionRing = ring
    }

    // MARK: Private

    private func create(card: CardDefinition, animal: AnimalDefinition, observation: MarkerObservation) {
        guard let scene else { return }
        let anchor = AnchorEntity(world: observation.worldTransform)
        anchor.name = "card:\(card.id)"
        scene.addAnchor(anchor)

        let instance = AnimalInstance(
            speciesID: animal.id,
            cardID: card.id,
            markerID: card.markerID,
            anchor: anchor,
            initialTransform: observation.worldTransform,
            timestamp: observation.timestamp
        )
        instance.observationCount = 1
        instances[card.markerID] = instance

        Task { [weak self] in
            guard let self, let entity = await self.assetManager.makeEntity(for: animal.id) else { return }
            guard self.instances[card.markerID] === instance else { return }
            instance.entity = entity
            entity.orientation = Self.presentationYaw
            entity.position = Self.presentationYaw.act(-Self.bodyCenter(of: entity, headBodyLength: Float(animal.dimensions.headBodyLengthMeters * animal.scale)))
            anchor.addChild(entity)
            let label = self.makeLabel(for: animal, above: entity)
            label.isEnabled = self.labelsVisible
            anchor.addChild(label)
        }
    }

    private func refine(_ instance: AnimalInstance, with observation: MarkerObservation) {
        let current = instance.smoothedTransform
        let target = observation.worldTransform

        let currentPosition = SIMD3(current.columns.3.x, current.columns.3.y, current.columns.3.z)
        let targetPosition = SIMD3(target.columns.3.x, target.columns.3.y, target.columns.3.z)
        let currentRotation = simd_quatf(current)
        let targetRotation = simd_quatf(target)
        let angle = abs((targetRotation * currentRotation.inverse).angle)
        let wrappedAngle = min(angle, 2 * .pi - angle)

        let smoothed: simd_float4x4
        if simd_distance(currentPosition, targetPosition) > snapDistance || wrappedAngle > snapAngle {
            smoothed = target
            instance.observationCount = 1
        } else {
            // Converge quickly on first sightings, then favor stability.
            let alpha: Float = instance.observationCount < 8 ? 0.6 : 0.3
            let position = simd_mix(currentPosition, targetPosition, SIMD3(repeating: alpha))
            let rotation = simd_slerp(currentRotation, targetRotation, alpha)
            var matrix = simd_float4x4(rotation)
            matrix.columns.3 = SIMD4(position, 1)
            smoothed = matrix
            instance.observationCount += 1
        }

        instance.smoothedTransform = smoothed
        instance.lastSeen = observation.timestamp
        instance.anchor.transform = Transform(matrix: smoothed)
    }

    private func makeLabel(for animal: AnimalDefinition, above entity: Entity) -> Entity {
        let root = Entity()
        root.name = Self.labelName

        let text = animal.usesStandIn ? "\(animal.displayName) · stand-in" : animal.displayName
        let textMesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.0002,
            font: Brand.uiFont(size: 0.008, weight: 600),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byTruncatingTail
        )
        let textEntity = ModelEntity(mesh: textMesh, materials: [UnlitMaterial(color: UIColor(hex: "#F6F5EF"))])
        let textBounds = textMesh.bounds
        textEntity.position = [-textBounds.center.x, -textBounds.center.y, 0.0003]

        let padding: Float = 0.004
        let plate = ModelEntity(
            mesh: .generatePlane(width: textBounds.extents.x + padding * 2, height: textBounds.extents.y + padding * 2, cornerRadius: padding),
            materials: [UnlitMaterial(color: UIColor(hex: "#1B1B1B").withAlphaComponent(0.82))]
        )

        let top = entity.visualBounds(relativeTo: entity).max.y
        root.position = [0, top + 0.02, 0]
        root.addChild(plate)
        root.addChild(textEntity)
        root.components.set(BillboardComponent())
        return root
    }

    private func makeSelectionRing(for instance: AnimalInstance) -> Entity {
        let radius: Float
        if let entity = instance.entity {
            let extents = entity.visualBounds(relativeTo: entity).extents
            radius = max(extents.x, extents.z) / 2 + 0.01
        } else {
            radius = 0.03
        }
        let ring = ModelEntity(
            mesh: .generateCylinder(height: 0.0005, radius: radius),
            materials: [UnlitMaterial(color: UIColor(hex: "#F6F5EF").withAlphaComponent(0.35))]
        )
        ring.name = "selection"
        ring.position = [0, 0.0003, 0]
        return ring
    }

    /// Point in the entity's own space that should sit on the tag: the middle of the head and body.
    /// Models are normalized nose-along-+Z, so this ignores a tail trailing behind. Models shorter than
    /// the head-body length (e.g. a skull) are centered on their bounds.
    private static func bodyCenter(of entity: Entity, headBodyLength: Float) -> SIMD3<Float> {
        let bounds = entity.visualBounds(relativeTo: entity)
        var center = bounds.center
        center.y = 0
        if headBodyLength > 0, headBodyLength < bounds.extents.z {
            center.z = bounds.max.z - headBodyLength / 2
        }
        return center
    }

    private func publish() {
        let summaries = instances.values
            .sorted { $0.markerID < $1.markerID }
            .map { AnimalInstanceSummary(id: $0.id, speciesID: $0.speciesID, markerID: $0.markerID, trackingState: $0.trackingState) }
        onInstancesChanged?(summaries)
    }
}
