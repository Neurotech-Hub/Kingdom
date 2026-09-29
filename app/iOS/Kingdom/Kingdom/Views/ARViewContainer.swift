import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let sessionManager: ARSessionManager
    let onSelect: (UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(sessionManager: sessionManager, onSelect: onSelect)
    }

    func makeUIView(context: Context) -> ARView {
        // A zero-sized ARView, or one whose session starts before it is in a window, can render virtual
        // content with a projection that does not match the camera image.
        let arView = ARView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), cameraMode: .ar, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        sessionManager.attach(to: arView)
        Self.runWhenAttached(arView, sessionManager: sessionManager)

        let coaching = ARCoachingOverlayView()
        coaching.session = arView.session
        coaching.goal = .tracking
        coaching.activatesAutomatically = true
        coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.addSubview(coaching)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tap)
        context.coordinator.arView = arView
        return arView
    }

    private static func runWhenAttached(_ arView: ARView, sessionManager: ARSessionManager, attemptsLeft: Int = 30) {
        DispatchQueue.main.async {
            if (arView.window != nil && arView.bounds.width > 1) || attemptsLeft == 0 {
                sessionManager.run()
            } else {
                runWhenAttached(arView, sessionManager: sessionManager, attemptsLeft: attemptsLeft - 1)
            }
        }
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.onSelect = onSelect
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        uiView.session.pause()
    }

    final class Coordinator: NSObject {
        let sessionManager: ARSessionManager
        var onSelect: (UUID?) -> Void
        weak var arView: ARView?

        init(sessionManager: ARSessionManager, onSelect: @escaping (UUID?) -> Void) {
            self.sessionManager = sessionManager
            self.onSelect = onSelect
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let arView else { return }
            let point = recognizer.location(in: arView)
            let id = arView.entity(at: point).flatMap { sessionManager.anchorManager.instanceID(for: $0) }
            onSelect(id)
        }
    }
}
