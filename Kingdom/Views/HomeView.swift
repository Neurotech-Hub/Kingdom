import SwiftUI

/// Catalog home: a grid of every animal with a rendered preview, plus the entry point to the AR viewer.
struct HomeView: View {
    @Bindable var appState: AppState
    let catalog: AnimalCatalog

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 14)]

    private var entries: [(card: CardDefinition, animal: AnimalDefinition)] {
        catalog.cards
            .sorted { $0.markerID < $1.markerID }
            .compactMap { card in catalog.animal(id: card.animalID).map { (card, $0) } }
    }

    @State private var thumbnails = AnimalThumbnailStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    arButton
                    Text("ANIMALS")
                        .font(Brand.font(12, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(entries, id: \.card.id) { entry in
                            NavigationLink(value: entry.animal.id) {
                                AnimalCardView(animal: entry.animal, markerID: entry.card.markerID, thumbnail: thumbnails.images[entry.animal.id])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .foregroundStyle(Brand.charcoal)
            .background(Brand.mist.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { animalID in
                if let animal = catalog.animal(id: animalID) {
                    AnimalDetailView(
                        animal: animal,
                        markerID: catalog.cards.first { $0.animalID == animalID }?.markerID
                    )
                }
            }
        }
        .tint(Brand.forest)
        .onAppear {
            for entry in entries {
                thumbnails.request(entry.animal)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("KingdomMark")
                .resizable()
                .scaledToFit()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Kingdom")
                    .font(Brand.font(28, weight: .bold))
                Text("ANIMALS IN REAL SCALE")
                    .font(Brand.font(11, weight: .medium))
                    .tracking(2.5)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var arButton: some View {
        Button {
            appState.isARPresented = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "viewfinder")
                    .font(.system(size: 18, weight: .semibold))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open AR viewer")
                        .font(Brand.font(17, weight: .semibold))
                    Text(ARSessionManager.isSupported ? "Point at Kingdom tags to place animals at true scale" : "Requires an ARKit-capable device")
                        .font(Brand.font(12))
                        .opacity(0.75)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(Brand.mist)
            .padding(.horizontal, 18)
            .frame(height: 64)
            .background(Brand.charcoal, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .disabled(!ARSessionManager.isSupported)
        .opacity(ARSessionManager.isSupported ? 1 : 0.5)
    }
}

private struct AnimalCardView: View {
    let animal: AnimalDefinition
    let markerID: Int
    let thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView()
                }
            }
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(Brand.sand.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text(animal.displayName)
                    .font(Brand.font(15, weight: .semibold))
                    .lineLimit(1)
                if let scientificName = animal.scientificName {
                    Text(scientificName)
                        .font(Brand.italicFont(12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack {
                Text("Tag #\(markerID)")
                Spacer()
                Text(DisplayFormat.lengthString(meters: animal.dimensions.headBodyLengthMeters))
            }
            .font(Brand.font(11, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}
