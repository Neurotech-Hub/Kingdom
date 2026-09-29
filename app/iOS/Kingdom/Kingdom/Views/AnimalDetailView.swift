import SwiftUI

/// Interactive 3D model above the animal's catalog details.
struct AnimalDetailView: View {
    let animal: AnimalDefinition
    let markerID: Int?

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                AnimalModelView(animal: animal)
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)

                Label("Drag to rotate", systemImage: "hand.draw")
                    .font(Brand.font(12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .allowsHitTesting(false)
            }
            .background(Brand.sand.opacity(0.45))

            AnimalInfoView(animal: animal, markerID: markerID)
        }
        .background(Brand.mist.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }
}
