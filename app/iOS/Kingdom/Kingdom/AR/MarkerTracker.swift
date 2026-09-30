import ARKit
import simd

/// A marker seen in one camera frame, already expressed in ARKit world space.
///
/// The transform uses the Kingdom card frame: origin at the tag center, +Y out of the card surface,
/// +X toward the card's right edge and +Z toward its bottom edge (as the artwork reads upright).
nonisolated struct MarkerObservation: Sendable {
    let markerID: Int
    var worldTransform: simd_float4x4
    /// Camera position in world space for the frame the tag was detected in.
    let cameraPosition: SIMD3<Float>
    let timestamp: TimeInterval
    /// Detector confidence; higher is better.
    let quality: Float
    let distanceMeters: Float
}

/// Recognizes Kingdom cards in AR frames. Implementations can swap marker technologies freely.
@MainActor
protocol MarkerTracker: AnyObject {
    var onObservations: (([MarkerObservation]) -> Void)? { get set }
    func process(frame: ARFrame)
    func reset()
}

nonisolated enum MarkerPose {
    /// Kingdom card frame expressed in the AprilTag frame (x right, y down, z into the tag).
    static let cardInTag = simd_float4x4(columns: (
        SIMD4(1, 0, 0, 0),
        SIMD4(0, 0, -1, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(0, 0, 0, 1)
    ))

    /// ARKit camera frame (x right, y up, z backward) from the optical frame (x right, y down, z forward).
    static let opticalInARCamera = simd_float4x4(diagonal: SIMD4(1, -1, -1, 1))

    /// World transform of the card given the tag pose in the optical frame and the ARKit camera transform.
    static func worldTransform(cameraTransform: simd_float4x4, tagRotation: simd_double3x3, tagTranslation: SIMD3<Double>) -> simd_float4x4 {
        let tagInOptical = simd_float4x4(columns: (
            SIMD4(SIMD3<Float>(tagRotation.columns.0), 0),
            SIMD4(SIMD3<Float>(tagRotation.columns.1), 0),
            SIMD4(SIMD3<Float>(tagRotation.columns.2), 0),
            SIMD4(SIMD3<Float>(tagTranslation), 1)
        ))
        return cameraTransform * opticalInARCamera * tagInOptical * cardInTag
    }

    /// Snaps a nearly horizontal card so its +Y matches world up, keeping position and heading.
    ///
    /// Small tags give noisy tilt estimates; cards resting on a table are assumed level.
    /// Returns the input unchanged when the card is tilted beyond `maxTiltRadians`.
    static func leveled(_ transform: simd_float4x4, maxTiltRadians: Float = .pi / 7) -> simd_float4x4 {
        let up = simd_normalize(SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z))
        let worldUp = SIMD3<Float>(0, 1, 0)
        guard acos(simd_clamp(simd_dot(up, worldUp), -1, 1)) <= maxTiltRadians else { return transform }

        var forward = SIMD3(transform.columns.2.x, 0, transform.columns.2.z)
        if simd_length(forward) < 1e-4 {
            forward = SIMD3(-transform.columns.1.x, 0, -transform.columns.1.z)
        }
        forward = simd_normalize(forward)
        let right = simd_normalize(simd_cross(worldUp, forward))
        return simd_float4x4(columns: (
            SIMD4(right, 0),
            SIMD4(worldUp, 0),
            SIMD4(forward, 0),
            transform.columns.3
        ))
    }
}
