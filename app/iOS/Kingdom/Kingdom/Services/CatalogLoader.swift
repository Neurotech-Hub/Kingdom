import Foundation

nonisolated enum CatalogLoader {
    enum LoadError: Error, LocalizedError {
        case missingResource(String)
        case duplicateMarkerID(Int)
        case duplicateAnimalID(String)
        case unknownAnimal(cardID: String, animalID: String)

        var errorDescription: String? {
            switch self {
            case .missingResource(let name): "Missing bundled resource \(name)."
            case .duplicateMarkerID(let id): "Marker ID \(id) is assigned to more than one card."
            case .duplicateAnimalID(let id): "Animal ID \(id) is defined more than once."
            case .unknownAnimal(let cardID, let animalID): "Card \(cardID) references unknown animal \(animalID)."
            }
        }
    }

    static func loadBundled(bundle: Bundle = .main) throws -> AnimalCatalog {
        guard let url = bundle.url(forResource: "AnimalCatalog", withExtension: "json") else {
            throw LoadError.missingResource("AnimalCatalog.json")
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> AnimalCatalog {
        let catalog = try JSONDecoder().decode(AnimalCatalog.self, from: data)
        try validate(catalog)
        return catalog
    }

    static func validate(_ catalog: AnimalCatalog) throws {
        var animalIDs = Set<String>()
        for animal in catalog.animals where !animalIDs.insert(animal.id).inserted {
            throw LoadError.duplicateAnimalID(animal.id)
        }
        var markerIDs = Set<Int>()
        for card in catalog.cards {
            guard markerIDs.insert(card.markerID).inserted else { throw LoadError.duplicateMarkerID(card.markerID) }
            guard animalIDs.contains(card.animalID) else {
                throw LoadError.unknownAnimal(cardID: card.id, animalID: card.animalID)
            }
        }
    }
}
