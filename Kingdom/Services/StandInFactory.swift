import RealityKit
import UIKit

/// Builds simple, correctly sized placeholder animals from catalog dimensions.
///
/// Output follows the canonical model frame: nose along +Z, up along +Y, feet on y = 0, meters.
enum StandInFactory {
    static func makeEntity(for animal: AnimalDefinition) -> Entity {
        let root = Entity()
        root.name = "standIn:\(animal.id)"

        let length = Float(animal.dimensions.headBodyLengthMeters)
        let height = Float(animal.dimensions.shoulderHeightMeters)
        let tailLength = Float(animal.dimensions.tailLengthMeters ?? 0)

        let coat = material(animal.standIn.color)
        let accent = material(animal.standIn.accentColor)
        let eye = material("#0E0E0E", roughness: 0.2)

        // Body: ellipsoid covering the rear ~65% of head-body length, resting on the ground.
        let bodyLength = length * 0.68
        let bodyHeight = height * 0.95
        let bodyWidth = height * 0.9
        let bodyCenterZ = -length / 2 + bodyLength / 2
        root.addChild(ellipsoid(size: [bodyWidth, bodyHeight, bodyLength], at: [0, bodyHeight / 2 + height * 0.05, bodyCenterZ], material: coat))

        // Head: smaller ellipsoid forward, nose reaching +length/2.
        let headLength = length * 0.36
        let headSize: SIMD3<Float> = [height * 0.62, height * 0.58, headLength]
        let headCenter: SIMD3<Float> = [0, height * 0.55, length / 2 - headLength / 2]
        root.addChild(ellipsoid(size: headSize, at: headCenter, material: coat))

        // Ears and eyes.
        let earRadius: Float = animal.standIn.bodyPlan == .murid ? height * 0.16 : height * 0.11
        for side: Float in [-1, 1] {
            let earPosition: SIMD3<Float> = [side * headSize.x * 0.32, headCenter.y + headSize.y * 0.45, headCenter.z - headLength * 0.15]
            root.addChild(ellipsoid(size: [earRadius * 2, earRadius * 2, earRadius * 0.6], at: earPosition, material: accent))

            let eyePosition: SIMD3<Float> = [side * headSize.x * 0.38, headCenter.y + headSize.y * 0.12, headCenter.z + headLength * 0.2]
            root.addChild(ellipsoid(size: SIMD3(repeating: height * 0.08), at: eyePosition, material: eye))
        }

        if tailLength > 0 {
            let tailStart: SIMD3<Float> = [0, height * 0.3, -length / 2]
            switch animal.standIn.bodyPlan {
            case .murid:
                // Thin tail sloping from the rump back down to the ground.
                let radius = height * 0.05
                let baseHeight = height * 0.15
                let droop = atan2(baseHeight - radius, tailLength)
                let mesh = MeshResource.generateCylinder(height: tailLength, radius: radius)
                let tail = ModelEntity(mesh: mesh, materials: [accent])
                // Cylinder axis is +Y; rotate it to point backward (-Z) and slightly down.
                tail.orientation = simd_quatf(angle: -(Float.pi / 2 + droop), axis: [1, 0, 0])
                let direction = tail.orientation.act([0, 1, 0])
                tail.position = SIMD3<Float>(0, baseHeight, tailStart.z) + direction * (tailLength / 2)
                root.addChild(tail)
            case .sciurid:
                // Bushy tail sweeping up behind the back.
                let tail = ellipsoid(size: [height * 0.55, height * 0.45, tailLength], at: .zero, material: coat)
                let lift = Float.pi / 3
                tail.orientation = simd_quatf(angle: lift, axis: [1, 0, 0])
                let direction = tail.orientation.act([0, 0, -1])
                tail.position = tailStart + direction * (tailLength / 2)
                root.addChild(tail)
            }
        }

        return root
    }

    private static func ellipsoid(size: SIMD3<Float>, at position: SIMD3<Float>, material: any RealityKit.Material) -> ModelEntity {
        let entity = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [material])
        entity.scale = size
        entity.position = position
        return entity
    }

    private static func material(_ hex: String, roughness: Float = 0.85) -> SimpleMaterial {
        var material = SimpleMaterial()
        material.color = .init(tint: UIColor(hex: hex))
        material.roughness = .init(floatLiteral: roughness)
        material.metallic = .init(floatLiteral: 0)
        return material
    }
}
