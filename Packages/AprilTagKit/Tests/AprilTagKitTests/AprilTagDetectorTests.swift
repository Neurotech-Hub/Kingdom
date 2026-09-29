import AprilTagKit
import CAprilTag
import CoreGraphics
import Foundation
import ImageIO
import simd
import XCTest

final class AprilTagDetectorTests: XCTestCase {
    /// Renders a tag36h11 code with the library itself, upsamples it, and checks the decode and pose.
    func testSyntheticTagDecodesWithPose() throws {
        try checkSyntheticTag(quadDecimate: 1)
    }

    /// The app detects with quad decimation; depth must still use full-resolution corners.
    func testSyntheticTagDecodesWithPoseWhenDecimated() throws {
        try checkSyntheticTag(quadDecimate: 2)
    }

    private func checkSyntheticTag(quadDecimate: Float) throws {
        let family = tag36h11_create()!
        defer { tag36h11_destroy(family) }

        let tagID: UInt32 = 3
        let tagImage = apriltag_to_image(family, tagID)!
        defer { image_u8_destroy(tagImage) }

        let cells = Int(tagImage.pointee.width)
        let scale = 24
        let margin = 40
        let side = cells * scale + margin * 2
        var pixels = [UInt8](repeating: 255, count: side * side)
        for y in 0..<(cells * scale) {
            for x in 0..<(cells * scale) {
                let value = tagImage.pointee.buf[(y / scale) * Int(tagImage.pointee.stride) + (x / scale)]
                pixels[(y + margin) * side + (x + margin)] = value
            }
        }

        let focal = 500.0
        let intrinsics = CameraIntrinsics(fx: focal, fy: focal, cx: Double(side) / 2, cy: Double(side) / 2)
        let borderPixels = Double(Int(family.pointee.width_at_border) * scale)
        let tagSize = 0.0208
        let expectedDepth = focal * tagSize / borderPixels

        let detector = AprilTagDetector(quadDecimate: quadDecimate)
        let detections = pixels.withUnsafeBytes { buffer in
            detector.detect(luma: buffer.baseAddress!, width: side, height: side, bytesPerRow: side, intrinsics: intrinsics, tagSize: tagSize)
        }

        XCTAssertEqual(detections.count, 1)
        let detection = try XCTUnwrap(detections.first)
        XCTAssertEqual(detection.id, Int(tagID))
        let translation = try XCTUnwrap(detection.translation)
        XCTAssertEqual(translation.z, expectedDepth, accuracy: expectedDepth * 0.02)
        XCTAssertEqual(translation.x, 0, accuracy: 0.001)
        XCTAssertEqual(translation.y, 0, accuracy: 0.001)

        // A fronto-parallel, upright tag has tag axes aligned with the optical frame.
        let rotation = try XCTUnwrap(detection.rotation)
        let identity = matrix_identity_double3x3
        for column in 0..<3 {
            for row in 0..<3 {
                XCTAssertEqual(rotation[column][row], identity[column][row], accuracy: 0.02)
            }
        }
    }

    /// Decodes every exported tag PNG copied into Fixtures by tools/tag-gen.
    func testExportedTagArtworkDecodes() throws {
        let fixtures = try XCTUnwrap(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let manifestURL = fixtures.appendingPathComponent("manifest.json")
        let manifest = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: manifestURL))
        XCTAssertFalse(manifest.isEmpty)

        let detector = AprilTagDetector(quadDecimate: 2)
        for (fileName, expectedID) in manifest {
            let url = fixtures.appendingPathComponent(fileName)
            let (pixels, width, height) = try loadGrayscale(url)
            let intrinsics = CameraIntrinsics(fx: 800, fy: 800, cx: Double(width) / 2, cy: Double(height) / 2)
            let detections = pixels.withUnsafeBytes { buffer in
                detector.detect(luma: buffer.baseAddress!, width: width, height: height, bytesPerRow: width, intrinsics: intrinsics, tagSize: 0.0208)
            }
            XCTAssertEqual(detections.map(\.id), [expectedID], fileName)

            // Artwork must decode upright so the card frame (and animal heading) matches the printed text.
            let rotation = try XCTUnwrap(detections.first?.rotation, fileName)
            XCTAssertEqual(rotation[0][0], 1, accuracy: 0.05, fileName)
            XCTAssertEqual(rotation[1][1], 1, accuracy: 0.05, fileName)
        }
    }

    private func loadGrayscale(_ url: URL) throws -> ([UInt8], Int, Int) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 255, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        return (pixels, width, height)
    }
}
