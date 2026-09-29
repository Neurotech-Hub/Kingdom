import Foundation
import RealityKit
import simd

/// Loads, normalizes, caches and clones animal entities by animal ID.
///
/// Every returned entity uses the canonical animal frame: meters, nose along +Z, up along +Y,
/// lowest point on y = 0, centered on the origin in x/z.
@MainActor
final class AnimalAssetManager {
    private let catalog: AnimalCatalog
    private let bundle: Bundle
    private var prototypes: [String: Entity] = [:]
    private var inFlight: [String: Task<Entity, Never>] = [:]

    init(catalog: AnimalCatalog, bundle: Bundle = .main) {
        self.catalog = catalog
        self.bundle = bundle
    }

    func preload(animalIDs: [String]) async {
        for id in animalIDs {
            _ = await prototype(for: id)
        }
    }

    /// Returns an independent clone for placement under one card's anchor.
    func makeEntity(for animalID: String) async -> Entity? {
        guard let prototype = await prototype(for: animalID) else { return nil }
        return prototype.clone(recursive: true)
    }

    private func prototype(for animalID: String) async -> Entity? {
        if let cached = prototypes[animalID] { return cached }
        guard let animal = catalog.animal(id: animalID) else { return nil }

        if let task = inFlight[animalID] {
            return await task.value
        }
        let task = Task { await self.buildPrototype(for: animal) }
        inFlight[animalID] = task
        let entity = await task.value
        inFlight[animalID] = nil
        prototypes[animalID] = entity
        return entity
    }

    private func buildPrototype(for animal: AnimalDefinition) async -> Entity {
        let model: Entity
        var fit: AnimalDefinition.Fit?
        var yawDegrees = 0.0

        if let asset = animal.asset,
           let url = bundle.url(forResource: asset.fileName, withExtension: asset.fileExtension),
           let loaded = try? await Entity(contentsOf: url) {
            model = loaded
            fit = asset.fit
            yawDegrees = asset.yawOffsetDegrees
        } else {
            model = StandInFactory.makeEntity(for: animal)
        }

        let container = Entity()
        container.name = "animal:\(animal.id)"
        let normalizer = Entity()
        normalizer.name = "normalizer"
        normalizer.addChild(model)
        container.addChild(normalizer)

        let bounds = model.visualBounds(relativeTo: normalizer)
        normalizer.transform = Self.normalization(
            boundsMin: bounds.min,
            boundsMax: bounds.max,
            fit: fit,
            yawDegrees: yawDegrees,
            extraScale: Float(animal.scale)
        )

        let normalizedBounds = container.visualBounds(relativeTo: container)
        container.components.set(CollisionComponent(shapes: [
            ShapeResource.generateBox(size: normalizedBounds.extents).offsetBy(translation: normalizedBounds.center),
        ]))
        applyGroundingShadows(to: container)
        return container
    }

    private func applyGroundingShadows(to entity: Entity) {
        if entity.components.has(ModelComponent.self) {
            entity.components.set(GroundingShadowComponent(castsShadow: true))
        }
        for child in entity.children {
            applyGroundingShadows(to: child)
        }
    }

    /// Transform that scales, rotates and grounds a model given its bounds in its own parent space.
    ///
    /// Stand-ins pass `fit == nil` because they are generated in meters already.
    nonisolated static func normalization(
        boundsMin: SIMD3<Float>,
        boundsMax: SIMD3<Float>,
        fit: AnimalDefinition.Fit?,
        yawDegrees: Double,
        extraScale: Float = 1
    ) -> Transform {
        let extents = boundsMax - boundsMin
        var scale: Float = 1
        if let fit {
            switch fit.mode {
            case .longestHorizontalExtent:
                let longest = max(extents.x, extents.z)
                if longest > 0 { scale = Float(fit.lengthMeters) / longest }
            case .metersPerUnit:
                scale = Float(fit.lengthMeters)
            }
        }
        scale *= extraScale

        let rotation = simd_quatf(angle: Float(yawDegrees * .pi / 180), axis: [0, 1, 0])
        let center = (boundsMin + boundsMax) / 2
        var offset = rotation.act(center * scale)
        offset.y = boundsMin.y * scale

        return Transform(scale: SIMD3(repeating: scale), rotation: rotation, translation: -offset)
    }
}
