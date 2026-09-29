import SceneKit
import UIKit

/// Builds SceneKit scenes for the catalog previews (home thumbnails and the detail viewer).
///
/// Previews use SceneKit rather than RealityKit: a SwiftUI `RealityView` in the same process leaves the
/// AR camera feed of `ARView` rendering black.
enum AnimalPreviewScene {
    static let modelNodeName = "model"

    /// Turns the nose (+Z) partly to the side for a three-quarter view.
    private static let initialYaw: Float = -.pi / 5

    /// A scene with the animal scaled to unit size at the origin, a camera and lights, or nil when the
    /// animal has no bundled model.
    nonisolated static func make(for animal: AnimalDefinition, bundle: Bundle = .main) -> SCNScene? {
        guard let asset = animal.asset,
              let url = bundle.url(forResource: asset.fileName, withExtension: asset.fileExtension),
              let source = try? SCNScene(url: url) else { return nil }

        let content = SCNNode()
        for child in source.rootNode.childNodes {
            content.addChildNode(child)
        }
        let turned = SCNNode()
        turned.simdOrientation = simd_quatf(angle: Float(asset.yawOffsetDegrees * .pi / 180), axis: [0, 1, 0])
        turned.addChildNode(content)

        let holder = SCNNode()
        holder.addChildNode(turned)
        let (minimum, maximum) = holder.boundingBox
        let low = SIMD3<Float>(minimum), high = SIMD3<Float>(maximum)
        let extents = high - low
        let scale = 1 / max(extents.max(), 1e-4)
        let center = (low + high) / 2
        turned.simdPosition = -center

        let model = SCNNode()
        model.name = modelNodeName
        model.simdScale = SIMD3(repeating: scale)
        model.simdOrientation = simd_quatf(angle: initialYaw, axis: [0, 1, 0])
        model.addChildNode(holder)

        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(model)
        scene.rootNode.addChildNode(makeCamera())
        for light in makeLights() {
            scene.rootNode.addChildNode(light)
        }
        return scene
    }

    /// Frames a unit-sized model at the origin from slightly above.
    nonisolated private static func makeCamera() -> SCNNode {
        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.01
        camera.zFar = 20
        let node = SCNNode()
        node.name = "camera"
        node.camera = camera
        node.simdPosition = [0, 0.7, 2.4]
        node.simdLook(at: .zero)
        return node
    }

    nonisolated private static func makeLights() -> [SCNNode] {
        var nodes: [SCNNode] = []
        for (position, intensity) in [(SIMD3<Float>(1.5, 2.5, 2), CGFloat(1100)), ([-2, 1, 1.5], 500), ([0, 1.5, -2.5], 600)] {
            let light = SCNLight()
            light.type = .directional
            light.intensity = intensity
            let node = SCNNode()
            node.light = light
            node.simdPosition = position
            node.simdLook(at: .zero)
            nodes.append(node)
        }
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 250
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        nodes.append(ambientNode)
        return nodes
    }
}

/// Renders each animal's preview once and keeps the image for the home grid.
@MainActor
@Observable
final class AnimalThumbnailStore {
    private(set) var images: [String: UIImage] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private let queue = DispatchQueue(label: "com.kingdom.thumbnails", qos: .userInitiated)

    /// Point size of the grid cell the image fills; rendered at screen scale.
    static let pointSize = CGSize(width: 180, height: 140)

    func request(_ animal: AnimalDefinition) {
        guard !requested.contains(animal.id) else { return }
        requested.insert(animal.id)
        let size = CGSize(width: Self.pointSize.width * 3, height: Self.pointSize.height * 3)
        queue.async { [weak self] in
            let image = Self.render(animal, size: size)
            DispatchQueue.main.async {
                guard let self, let image else { return }
                self.images[animal.id] = image
            }
        }
    }

    nonisolated private static func render(_ animal: AnimalDefinition, size: CGSize) -> UIImage? {
        guard let scene = AnimalPreviewScene.make(for: animal),
              let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = scene
        renderer.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
        renderer.autoenablesDefaultLighting = false
        let image = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
        return image.cgImage.map { UIImage(cgImage: $0, scale: 3, orientation: .up) }
    }
}
