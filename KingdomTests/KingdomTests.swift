//
//  KingdomTests.swift
//  KingdomTests
//
//  Created by Matt Gaidica on 9/29/26.
//

import Foundation
import RealityKit
import simd
import Testing
@testable import Kingdom

struct CatalogTests {
    @Test func bundledCatalogLoadsAndValidates() throws {
        let catalog = try CatalogLoader.loadBundled()
        #expect(catalog.marker.family == "tag36h11")
        #expect(abs(catalog.marker.tagSizeMeters - 0.0208) < 1e-9)

        let required = ["c57bl6j", "generic_rat", "red_squirrel", "gray_squirrel_skull", "fox_squirrel", "generic_mouse"]
        for id in required {
            #expect(catalog.animal(id: id) != nil, "missing \(id)")
        }
        #expect(catalog.animal(forMarkerID: 0)?.id == "c57bl6j")
        #expect(catalog.animal(forMarkerID: 1)?.id == "generic_rat")
    }

    @Test func bundledAssetsExist() throws {
        let catalog = try CatalogLoader.loadBundled()
        for animal in catalog.animals {
            guard let asset = animal.asset else { continue }
            #expect(Bundle.main.url(forResource: asset.fileName, withExtension: asset.fileExtension) != nil, "missing \(asset.fileName)")
        }
    }

    @Test func duplicateMarkerIDsAreRejected() throws {
        let json = """
        {
          "schemaVersion": 1,
          "marker": { "family": "tag36h11", "tagSize_m": 0.02 },
          "animals": [{
            "id": "a", "displayName": "A", "scale": 1,
            "dimensions": { "headBodyLength_m": 0.1, "shoulderHeight_m": 0.03 },
            "standIn": { "bodyPlan": "murid", "color": "#000000", "accentColor": "#FFFFFF" }
          }],
          "cards": [
            { "id": "c1", "markerID": 0, "animalID": "a" },
            { "id": "c2", "markerID": 0, "animalID": "a" }
          ]
        }
        """
        #expect(throws: CatalogLoader.LoadError.self) {
            try CatalogLoader.decode(Data(json.utf8))
        }
    }
}

struct MarkerPoseTests {
    private func expectClose(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 1e-4) {
        #expect(simd_distance(a, b) < tolerance, "\(a) != \(b)")
    }

    private func column(_ m: simd_float4x4, _ index: Int) -> SIMD3<Float> {
        let c = m[index]
        return SIMD3(c.x, c.y, c.z)
    }

    /// A tag facing the camera 30 cm ahead, with the camera at the world origin looking down -Z.
    @Test func frontalTagMapsToWorld() {
        let world = MarkerPose.worldTransform(
            cameraTransform: matrix_identity_float4x4,
            tagRotation: matrix_identity_double3x3,
            tagTranslation: SIMD3(0, 0, 0.3)
        )
        expectClose(column(world, 3), [0, 0, -0.3])
        // Card normal points back toward the camera.
        expectClose(column(world, 1), [0, 0, 1])
        // Card right edge stays on screen right; card bottom edge points down on screen.
        expectClose(column(world, 0), [1, 0, 0])
        expectClose(column(world, 2), [0, -1, 0])
    }

    /// Camera pitched straight down at a tag lying on a table, text reading upright on screen.
    @Test func tableTagIsLevelAndGrounded() {
        let pitchDown = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))
        var camera = pitchDown
        camera.columns.3 = [0, 0.4, 0, 1]

        let world = MarkerPose.worldTransform(
            cameraTransform: camera,
            tagRotation: matrix_identity_double3x3,
            tagTranslation: SIMD3(0, 0, 0.4)
        )
        expectClose(column(world, 3), [0, 0, 0])
        expectClose(column(world, 1), [0, 1, 0])
    }

    @Test func levelingRemovesSmallTilt() {
        let tilt = simd_float4x4(simd_quatf(angle: 0.1, axis: simd_normalize(SIMD3<Float>(1, 0, 1))))
        var noisy = tilt
        noisy.columns.3 = [0.1, 0.2, 0.3, 1]

        let leveled = MarkerPose.leveled(noisy)
        expectClose(column(leveled, 1), [0, 1, 0])
        expectClose(column(leveled, 3), [0.1, 0.2, 0.3])
        #expect(abs(simd_dot(column(leveled, 0), column(leveled, 2))) < 1e-5)
    }

    @Test func levelingKeepsSteepTilt() {
        let wall = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))
        let result = MarkerPose.leveled(wall)
        expectClose(column(result, 1), column(wall, 1))
    }
}

struct NormalizationTests {
    @Test func fitsLongestHorizontalExtentAndGrounds() {
        let fit = AnimalDefinition.Fit(mode: .longestHorizontalExtent, lengthMeters: 0.1, reference: nil)
        let transform = AnimalAssetManager.normalization(
            boundsMin: [-5, 2, -20],
            boundsMax: [5, 10, 30],
            fit: fit,
            yawDegrees: 180
        )
        #expect(abs(transform.scale.x - 0.002) < 1e-6)

        let matrix = transform.matrix
        func apply(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let v = matrix * SIMD4(p, 1)
            return SIMD3(v.x, v.y, v.z)
        }
        // Bottom lands on y = 0, horizontal center lands on the origin, nose (+Z) flips to -Z.
        #expect(abs(apply([0, 2, 5]).y) < 1e-6)
        let center = apply([0, 6, 5])
        #expect(abs(center.x) < 1e-6 && abs(center.z) < 1e-6)
        #expect(apply([0, 6, 30]).z < 0)
    }
}

@MainActor
struct AssetPipelineTests {
    @Test func assetsNormalizeToCatalogScale() async throws {
        let catalog = try CatalogLoader.loadBundled()
        let manager = AnimalAssetManager(catalog: catalog)

        for animal in catalog.animals {
            let entity = try #require(await manager.makeEntity(for: animal.id))
            let bounds = entity.visualBounds(relativeTo: entity)
            #expect(abs(bounds.min.y) < 0.001, "\(animal.id) is not grounded: minY \(bounds.min.y)")

            let longest = max(bounds.extents.x, bounds.extents.z)
            if let fit = animal.asset?.fit, fit.mode == .longestHorizontalExtent {
                #expect(abs(Double(longest) - fit.lengthMeters * animal.scale) < 0.002 * animal.scale, "\(animal.id) length \(longest)")
            } else {
                // Stand-ins span head-body length plus some of the tail.
                #expect(Double(longest) >= animal.dimensions.headBodyLengthMeters * animal.scale * 0.95, "\(animal.id) length \(longest)")
                #expect(Double(longest) <= (animal.dimensions.headBodyLengthMeters + (animal.dimensions.tailLengthMeters ?? 0)) * animal.scale * 1.05)
            }
        }
    }

    /// Animals are longer nose-to-tail than they are wide, so a normalized model must be longest along Z.
    @Test func assetsAreNormalizedNoseAlongZ() async throws {
        let catalog = try CatalogLoader.loadBundled()
        let manager = AnimalAssetManager(catalog: catalog)

        for animal in catalog.animals where animal.asset != nil {
            let entity = try #require(await manager.makeEntity(for: animal.id))
            let extents = entity.visualBounds(relativeTo: entity).extents
            print("normalized extents \(animal.id): x \(extents.x) y \(extents.y) z \(extents.z)")
            #expect(extents.z > extents.x, "\(animal.id) is longest along X: \(extents)")
        }
    }

    @Test func clonesAreIndependent() async throws {
        let catalog = try CatalogLoader.loadBundled()
        let manager = AnimalAssetManager(catalog: catalog)
        let first = try #require(await manager.makeEntity(for: "generic_rat"))
        let second = try #require(await manager.makeEntity(for: "generic_rat"))
        #expect(first !== second)
        first.position = [1, 0, 0]
        #expect(second.position == .zero)
    }
}
