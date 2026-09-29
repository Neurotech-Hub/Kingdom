import Foundation

/// Static, catalog-driven description of one animal. Identified by a stable `id`, never by display name.
nonisolated struct AnimalDefinition: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    var commonName: String?
    var scientificName: String?
    var strainOrStock: String?
    var taxonGroup: String?
    var sex: String?
    var age: String?
    var bodyMassGrams: Double?
    var provenance: String?
    var notes: String?
    /// Extra multiplier on top of the physical fit, set from on-device ruler checks against the tag.
    var scale: Double
    var dimensions: Dimensions
    var asset: Asset?
    var standIn: StandIn

    nonisolated struct Dimensions: Codable, Hashable, Sendable {
        var headBodyLengthMeters: Double
        var tailLengthMeters: Double?
        var shoulderHeightMeters: Double

        enum CodingKeys: String, CodingKey {
            case headBodyLengthMeters = "headBodyLength_m"
            case tailLengthMeters = "tailLength_m"
            case shoulderHeightMeters = "shoulderHeight_m"
        }
    }

    nonisolated struct Asset: Codable, Hashable, Sendable {
        var fileName: String
        var fileExtension: String
        /// Rotation about +Y that turns the model so its nose points along +Z.
        var yawOffsetDegrees: Double
        var fit: Fit

        enum CodingKeys: String, CodingKey {
            case fileName
            case fileExtension
            case yawOffsetDegrees = "yawOffset_deg"
            case fit
        }
    }

    nonisolated struct Fit: Codable, Hashable, Sendable {
        enum Mode: String, Codable, Sendable {
            /// Uniformly scale so max(extent.x, extent.z) equals `lengthMeters`.
            case longestHorizontalExtent
            /// Uniformly scale by `lengthMeters` interpreted as meters per model unit.
            case metersPerUnit
        }

        var mode: Mode
        var lengthMeters: Double
        /// Human-readable description of what `lengthMeters` measures on this asset.
        var reference: String?

        enum CodingKeys: String, CodingKey {
            case mode
            case lengthMeters = "length_m"
            case reference
        }
    }

    nonisolated struct StandIn: Codable, Hashable, Sendable {
        enum BodyPlan: String, Codable, Sendable {
            case murid
            case sciurid
        }

        var bodyPlan: BodyPlan
        var color: String
        var accentColor: String
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case commonName
        case scientificName
        case strainOrStock
        case taxonGroup
        case sex
        case age
        case bodyMassGrams = "bodyMass_g"
        case provenance
        case notes
        case scale
        case dimensions
        case asset
        case standIn
    }

    var usesStandIn: Bool { asset == nil }
}
