import Foundation

/// A physical Kingdom tag. Maps a machine-readable marker ID to an animal.
nonisolated struct CardDefinition: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let markerID: Int
    let animalID: String
}

nonisolated struct MarkerConfiguration: Codable, Hashable, Sendable {
    var family: String
    /// Edge length of the tag's outer black border, in meters.
    var tagSizeMeters: Double

    enum CodingKeys: String, CodingKey {
        case family
        case tagSizeMeters = "tagSize_m"
    }
}

nonisolated struct AnimalCatalog: Codable, Sendable {
    var schemaVersion: Int
    var marker: MarkerConfiguration
    var animals: [AnimalDefinition]
    var cards: [CardDefinition]

    func animal(id: String) -> AnimalDefinition? {
        animals.first { $0.id == id }
    }

    func card(markerID: Int) -> CardDefinition? {
        cards.first { $0.markerID == markerID }
    }

    func animal(forMarkerID markerID: Int) -> AnimalDefinition? {
        card(markerID: markerID).flatMap { animal(id: $0.animalID) }
    }
}
