import SwiftUI

struct AnimalInfoView: View {
    let animal: AnimalDefinition
    let markerID: Int?
    /// Live tracking state when shown from the AR viewer; nil when browsing the catalog.
    var trackingState: AnimalInstance.TrackingState? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(animal.displayName)
                        .font(Brand.font(24, weight: .bold))
                    if let scientificName = animal.scientificName {
                        Text(scientificName)
                            .font(Brand.italicFont(16))
                            .foregroundStyle(.secondary)
                    }
                    if let commonName = animal.commonName, commonName != animal.displayName {
                        Text(commonName)
                            .font(Brand.font(14))
                            .foregroundStyle(.secondary)
                    }
                }

                scaleBadge

                VStack(spacing: 0) {
                    row("Strain / stock", animal.strainOrStock)
                    row("Sex", animal.sex)
                    row("Age", animal.age)
                    row("Body mass", animal.bodyMassGrams.map(DisplayFormat.massString(grams:)))
                    row("Head–body length", DisplayFormat.lengthString(meters: animal.dimensions.headBodyLengthMeters))
                    row("Tail length", animal.dimensions.tailLengthMeters.map(DisplayFormat.lengthString(meters:)))
                    row("Model", animal.provenance)
                    row("Tag", tagDescription)
                }

                if let notes = animal.notes {
                    Text(notes)
                        .font(Brand.font(14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .foregroundStyle(Brand.charcoal)
        .background(Brand.mist)
    }

    private var scaleBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "ruler")
            Text(animal.usesStandIn ? "True scale · stand-in geometry" : "True scale · 1:1")
                .font(Brand.font(13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .foregroundStyle(Brand.mist)
        .background(animal.usesStandIn ? Brand.clay : Brand.forest, in: Capsule())
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Brand.font(14))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 16)
                Text(value)
                    .font(Brand.font(14, weight: .medium))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 8)
            Divider()
        }
    }

    private var tagDescription: String? {
        guard let markerID else { return nil }
        guard let trackingState else { return "#\(markerID)" }
        let state = switch trackingState {
        case .detected: "Detected"
        case .tracking: "Tracking"
        case .stale: "Holding position"
        }
        return "#\(markerID) · \(state)"
    }
}
