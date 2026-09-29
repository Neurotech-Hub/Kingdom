import CAprilTag
import Foundation
import simd

/// Pinhole intrinsics in pixels, matching the image passed to the detector.
public struct CameraIntrinsics: Sendable, Equatable {
    public var fx: Double
    public var fy: Double
    public var cx: Double
    public var cy: Double

    public init(fx: Double, fy: Double, cx: Double, cy: Double) {
        self.fx = fx
        self.fy = fy
        self.cx = cx
        self.cy = cy
    }
}

/// A decoded tag36h11 marker.
///
/// `rotation` and `translation` map tag coordinates into the camera optical frame using the
/// AprilTag / OpenCV convention: camera x right, y down, z forward; tag x right, y down,
/// z into the tag. Translation is in meters.
public struct AprilTagDetection: Sendable {
    public let id: Int
    public let hamming: Int
    public let decisionMargin: Float
    public let center: SIMD2<Double>
    public let corners: [SIMD2<Double>]
    public let rotation: simd_double3x3?
    public let translation: SIMD3<Double>?
    public let poseError: Double?
}

/// Thin wrapper around the AprilRobotics C detector configured for tag36h11.
///
/// The underlying detector is not reentrant; calls to `detect` are serialized internally.
public final class AprilTagDetector: @unchecked Sendable {
    private let detector: UnsafeMutablePointer<apriltag_detector_t>
    private let family: UnsafeMutablePointer<apriltag_family_t>
    private let lock = NSLock()

    public init(quadDecimate: Float = 2.0, quadSigma: Float = 0.0, threads: Int = 2, refineEdges: Bool = true, maxHammingCorrection: Int = 1) {
        family = tag36h11_create()
        detector = apriltag_detector_create()
        apriltag_detector_add_family_bits(detector, family, Int32(maxHammingCorrection))
        detector.pointee.quad_decimate = quadDecimate
        detector.pointee.quad_sigma = quadSigma
        detector.pointee.nthreads = Int32(max(1, threads))
        detector.pointee.refine_edges = refineEdges
    }

    deinit {
        apriltag_detector_destroy(detector)
        tag36h11_destroy(family)
    }

    /// Detects tags in an 8-bit grayscale image.
    ///
    /// - Parameters:
    ///   - intrinsics: When provided with `tagSize`, a pose is estimated for each detection.
    ///   - tagSize: Edge length of the tag's outer black border, in meters.
    public func detect(
        luma: UnsafeRawPointer,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        intrinsics: CameraIntrinsics? = nil,
        tagSize: Double? = nil
    ) -> [AprilTagDetection] {
        lock.lock()
        defer { lock.unlock() }

        var image = image_u8_t(
            width: Int32(width),
            height: Int32(height),
            stride: Int32(bytesPerRow),
            buf: UnsafeMutablePointer(mutating: luma.assumingMemoryBound(to: UInt8.self))
        )

        guard let results = apriltag_detector_detect(detector, &image) else { return [] }
        defer { apriltag_detections_destroy(results) }

        let count = Int(zarray_size(results))
        var detections: [AprilTagDetection] = []
        detections.reserveCapacity(count)

        for index in 0..<count {
            var detPointer: UnsafeMutablePointer<apriltag_detection_t>?
            zarray_get(results, Int32(index), &detPointer)
            guard let det = detPointer else { continue }

            let p = det.pointee.p
            let corners = [
                SIMD2(p.0.0, p.0.1),
                SIMD2(p.1.0, p.1.1),
                SIMD2(p.2.0, p.2.1),
                SIMD2(p.3.0, p.3.1),
            ]

            var rotation: simd_double3x3?
            var translation: SIMD3<Double>?
            var poseError: Double?

            if let intrinsics, let tagSize {
                var info = apriltag_detection_info_t(
                    det: det,
                    tagsize: tagSize,
                    fx: intrinsics.fx,
                    fy: intrinsics.fy,
                    cx: intrinsics.cx,
                    cy: intrinsics.cy
                )
                var pose = apriltag_pose_t()
                poseError = estimate_tag_pose(&info, &pose)
                if let R = pose.R, let t = pose.t {
                    rotation = simd_double3x3(rows: (0..<3).map { row in
                        SIMD3((0..<3).map { col in matd_get(R, UInt32(row), UInt32(col)) })
                    })
                    translation = SIMD3(matd_get(t, 0, 0), matd_get(t, 1, 0), matd_get(t, 2, 0))
                    matd_destroy(R)
                    matd_destroy(t)
                }
            }

            detections.append(AprilTagDetection(
                id: Int(det.pointee.id),
                hamming: Int(det.pointee.hamming),
                decisionMargin: det.pointee.decision_margin,
                center: SIMD2(det.pointee.c.0, det.pointee.c.1),
                corners: corners,
                rotation: rotation,
                translation: translation,
                poseError: poseError
            ))
        }

        return detections
    }
}
