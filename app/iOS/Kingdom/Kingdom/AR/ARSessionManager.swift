import ARKit
import RealityKit
import UIKit

/// Configures world tracking and routes camera frames to the marker tracker.
@MainActor
final class ARSessionManager: NSObject {
    var onInstancesChanged: (([AnimalInstanceSummary]) -> Void)? {
        get { anchorManager.onInstancesChanged }
        set { anchorManager.onInstancesChanged = newValue }
    }
    var onTrackingMessage: ((String?) -> Void)?

    let catalog: AnimalCatalog
    let assetManager: AnimalAssetManager
    let anchorManager: AnimalAnchorManager
    private let markerTracker: MarkerTracker
    private weak var arView: ARView?

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    init(catalog: AnimalCatalog) {
        self.catalog = catalog
        assetManager = AnimalAssetManager(catalog: catalog)
        anchorManager = AnimalAnchorManager(catalog: catalog, assetManager: assetManager)
        markerTracker = AprilTagMarkerTracker(tagSizeMeters: catalog.marker.tagSizeMeters)
        super.init()
        markerTracker.onObservations = { [weak self] observations in
            self?.anchorManager.handle(observations)
            #if DEBUG
            self?.logDepthCheck(observations)
            #endif
        }
    }

    #if DEBUG
    private var didLogCamera = false
    private var lastDepthLog: TimeInterval = 0

    /// Compares each tag's AprilTag distance with ARKit's horizontal-plane estimate along the same ray.
    /// A ratio far from 1.0 means marker poses are placed at the wrong depth (and render at the wrong size).
    private func logDepthCheck(_ observations: [MarkerObservation]) {
        guard let session = arView?.session, let frame = session.currentFrame else { return }
        guard frame.timestamp - lastDepthLog >= 1 else { return }
        lastDepthLog = frame.timestamp

        let camera = frame.camera.transform
        let origin = SIMD3(camera.columns.3.x, camera.columns.3.y, camera.columns.3.z)
        for observation in observations {
            let tag = observation.worldTransform.columns.3
            let target = SIMD3(tag.x, tag.y, tag.z)
            let query = ARRaycastQuery(origin: origin, direction: simd_normalize(target - origin), allowing: .estimatedPlane, alignment: .horizontal)
            guard let hit = session.raycast(query).first else {
                print("[depth] tag \(observation.markerID): apriltag \(String(format: "%.3f", observation.distanceMeters)) m, no ARKit plane hit")
                continue
            }
            let hitPosition = SIMD3(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
            let arkit = simd_distance(origin, hitPosition)
            let apriltag = simd_distance(origin, target)
            print(String(format: "[depth] tag %d: apriltag %.3f m, ARKit plane %.3f m, ratio %.2f", observation.markerID, apriltag, arkit, apriltag / arkit))
        }
        if let observation = observations.first {
            logProjectionCheck(frame: frame, around: observation.worldTransform)
        }
    }

    /// Projects two points 5 cm apart with RealityKit (what we draw) and with ARKit (what the camera image
    /// shows). Their on-screen separations should match; a ratio far from 1.0 means virtual content is
    /// drawn at the wrong size relative to the camera feed.
    private func logProjectionCheck(frame: ARFrame, around transform: simd_float4x4) {
        guard let arView else { return }
        let center = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let right = simd_normalize(SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z))
        let a = center - right * 0.025
        let b = center + right * 0.025
        let orientation = arView.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let viewport = arView.bounds.size
        guard let realityA = arView.project(a), let realityB = arView.project(b) else { return }
        let arkitA = frame.camera.projectPoint(a, orientation: orientation, viewportSize: viewport)
        let arkitB = frame.camera.projectPoint(b, orientation: orientation, viewportSize: viewport)
        let reality = hypot(realityB.x - realityA.x, realityB.y - realityA.y)
        let arkit = hypot(arkitB.x - arkitA.x, arkitB.y - arkitA.y)
        print(String(format: "[projection] view %.0fx%.0f orientation %d, 5 cm spans RealityKit %.1f pt vs ARKit %.1f pt, ratio %.2f",
                     viewport.width, viewport.height, orientation.rawValue, reality, arkit, arkit > 0 ? reality / arkit : 0))
    }

    private func logCameraOnce(_ frame: ARFrame) {
        guard !didLogCamera else { return }
        didLogCamera = true
        let k = frame.camera.intrinsics
        let image = frame.capturedImage
        print("[camera] imageResolution \(frame.camera.imageResolution), capturedImage \(CVPixelBufferGetWidth(image))x\(CVPixelBufferGetHeight(image)), luma plane \(CVPixelBufferGetWidthOfPlane(image, 0))x\(CVPixelBufferGetHeightOfPlane(image, 0)), fx \(k.columns.0.x) fy \(k.columns.1.y) cx \(k.columns.2.x) cy \(k.columns.2.y)")
    }
    #endif

    func attach(to arView: ARView) {
        self.arView = arView
        arView.session.delegate = self
        anchorManager.attach(to: arView.scene)

        let assetManager = assetManager
        let ids = catalog.animals.map(\.id)
        Task { await assetManager.preload(animalIDs: ids) }
    }

    func run(resetting: Bool = false) {
        guard let arView, Self.isSupported else { return }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        if let format = Self.preferredVideoFormat() {
            configuration.videoFormat = format
        }
        let options: ARSession.RunOptions = resetting ? [.resetTracking, .removeExistingAnchors] : []
        arView.session.run(configuration, options: options)
    }

    func pause() {
        arView?.session.pause()
    }

    /// The camera image with rendered animals and labels, without the SwiftUI overlays.
    func captureSnapshot() async -> UIImage? {
        guard let arView else { return nil }
        return await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }

    /// Pauses tracking and removes every placed animal, e.g. when leaving the AR viewer.
    func stop() {
        anchorManager.reset()
        markerTracker.reset()
        arView?.session.pause()
    }

    func reset() {
        anchorManager.reset()
        markerTracker.reset()
        run(resetting: true)
    }

    /// Prefers a ~1920x1440 4:3 format: enough pixels for 2" tags without excessive detection cost.
    private static func preferredVideoFormat() -> ARConfiguration.VideoFormat? {
        let formats = ARWorldTrackingConfiguration.supportedVideoFormats
        return formats
            .filter { $0.imageResolution.width <= 1920 && $0.framesPerSecond >= 30 }
            .max { $0.imageResolution.width * $0.imageResolution.height < $1.imageResolution.width * $1.imageResolution.height }
    }

    fileprivate func handle(frame: ARFrame) {
        #if DEBUG
        logCameraOnce(frame)
        #endif
        markerTracker.process(frame: frame)
        anchorManager.updateTrackingStates(now: frame.timestamp)
    }

    fileprivate func handle(trackingState: ARCamera.TrackingState) {
        switch trackingState {
        case .normal:
            onTrackingMessage?(nil)
        case .notAvailable:
            onTrackingMessage?("Tracking unavailable")
        case .limited(.initializing):
            onTrackingMessage?("Move your device slowly")
        case .limited(.excessiveMotion):
            onTrackingMessage?("Slow down")
        case .limited(.insufficientFeatures):
            onTrackingMessage?("Point at a textured, well-lit surface")
        case .limited(.relocalizing):
            onTrackingMessage?("Relocalizing")
        case .limited:
            onTrackingMessage?("Tracking limited")
        }
    }
}

extension ARSessionManager: ARSessionDelegate {
    // ARSession delivers delegate callbacks on the main queue unless `delegateQueue` is set.
    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        MainActor.assumeIsolated {
            handle(frame: frame)
        }
    }

    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = camera.trackingState
        MainActor.assumeIsolated {
            handle(trackingState: state)
        }
    }

    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        MainActor.assumeIsolated {
            onTrackingMessage?(message)
        }
    }

    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        MainActor.assumeIsolated {
            onTrackingMessage?("Session interrupted")
        }
    }

    nonisolated func sessionInterruptionEnded(_ session: ARSession) {
        MainActor.assumeIsolated {
            reset()
        }
    }
}
