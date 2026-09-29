import SceneKit
import SwiftUI

/// Live, rotatable 3D view of one catalog animal, scaled to fit the view rather than true size.
struct AnimalModelView: UIViewRepresentable {
    let animal: AnimalDefinition

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.autoenablesDefaultLighting = false
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.maximumVerticalAngle = 60
        view.defaultCameraController.minimumVerticalAngle = -30

        let animal = animal
        DispatchQueue.global(qos: .userInitiated).async {
            let scene = AnimalPreviewScene.make(for: animal)
            DispatchQueue.main.async {
                guard let scene else { return }
                view.scene = scene
                view.pointOfView = scene.rootNode.childNode(withName: "camera", recursively: false)
                view.defaultCameraController.target = SCNVector3Zero
            }
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
