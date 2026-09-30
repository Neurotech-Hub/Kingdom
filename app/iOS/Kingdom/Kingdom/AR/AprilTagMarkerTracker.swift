import AprilTagKit
import ARKit
import simd

/// Detects tag36h11 AprilTags in the camera luma plane on a background queue.
@MainActor
final class AprilTagMarkerTracker: MarkerTracker {
    var onObservations: (([MarkerObservation]) -> Void)?

    /// Minimum seconds between detection passes.
    var minimumInterval: TimeInterval = 1.0 / 15.0
    /// Rejects weak decodes; tag36h11 decision margins for clean prints are typically well above 50.
    var minimumDecisionMargin: Float = 25

    private let tagSizeMeters: Double
    private let detector = AprilTagDetector(quadDecimate: 2, threads: 2, maxHammingCorrection: 1)
    private let queue = DispatchQueue(label: "com.kingdom.apriltag", qos: .userInitiated)
    private var isProcessing = false
    private var lastProcessedTimestamp: TimeInterval = 0
    private var generation = 0

    init(tagSizeMeters: Double) {
        self.tagSizeMeters = tagSizeMeters
    }

    func reset() {
        generation += 1
        lastProcessedTimestamp = 0
    }

    func process(frame: ARFrame) {
        guard !isProcessing, frame.timestamp - lastProcessedTimestamp >= minimumInterval else { return }
        guard case .normal = frame.camera.trackingState else { return }

        isProcessing = true
        lastProcessedTimestamp = frame.timestamp

        let input = FrameInput(
            pixelBuffer: frame.capturedImage,
            intrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            timestamp: frame.timestamp
        )
        let detector = detector
        let tagSize = tagSizeMeters
        let minimumMargin = minimumDecisionMargin
        let requestGeneration = generation

        queue.async {
            let observations = Self.detect(input: input, detector: detector, tagSize: tagSize, minimumMargin: minimumMargin)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isProcessing = false
                guard requestGeneration == self.generation, !observations.isEmpty else { return }
                self.onObservations?(observations)
            }
        }
    }

    private nonisolated static func detect(input: FrameInput, detector: AprilTagDetector, tagSize: Double, minimumMargin: Float) -> [MarkerObservation] {
        let buffer = input.pixelBuffer
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              let luma = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return [] }

        let k = input.intrinsics
        let intrinsics = CameraIntrinsics(
            fx: Double(k.columns.0.x),
            fy: Double(k.columns.1.y),
            cx: Double(k.columns.2.x),
            cy: Double(k.columns.2.y)
        )

        let detections = detector.detect(
            luma: luma,
            width: CVPixelBufferGetWidthOfPlane(buffer, 0),
            height: CVPixelBufferGetHeightOfPlane(buffer, 0),
            bytesPerRow: CVPixelBufferGetBytesPerRowOfPlane(buffer, 0),
            intrinsics: intrinsics,
            tagSize: tagSize
        )

        return detections.compactMap { detection in
            guard detection.hamming <= 1,
                  detection.decisionMargin >= minimumMargin,
                  let rotation = detection.rotation,
                  let translation = detection.translation else { return nil }
            let world = MarkerPose.worldTransform(
                cameraTransform: input.cameraTransform,
                tagRotation: rotation,
                tagTranslation: translation
            )
            return MarkerObservation(
                markerID: detection.id,
                worldTransform: MarkerPose.leveled(world),
                cameraPosition: SIMD3(input.cameraTransform.columns.3.x, input.cameraTransform.columns.3.y, input.cameraTransform.columns.3.z),
                timestamp: input.timestamp,
                quality: detection.decisionMargin,
                distanceMeters: Float(simd_length(translation))
            )
        }
    }
}

/// Frame data handed to the detection queue. The pixel buffer is only read.
private nonisolated struct FrameInput: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let intrinsics: simd_float3x3
    let cameraTransform: simd_float4x4
    let timestamp: TimeInterval
}
