import SwiftUI

struct OnboardingView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Image("KingdomMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                Text("Kingdom")
                    .font(Brand.font(40, weight: .bold))
                Text("ANIMALS IN REAL SCALE")
                    .font(Brand.font(12, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 18) {
                step(1, "Place one or more Kingdom tags on a flat surface.")
                step(2, "Point your camera at the tags.")
                step(3, "Move slowly until the animals appear, then walk around them.")
            }

            Spacer()

            Button(action: onStart) {
                Text("Start")
                    .font(Brand.font(17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(Brand.mist)
                    .background(Brand.charcoal, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
        }
        .padding(28)
        .foregroundStyle(Brand.charcoal)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.mist.ignoresSafeArea())
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("\(number)")
                .font(Brand.font(15, weight: .bold))
                .foregroundStyle(Brand.forest)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(Brand.font(17))
        }
    }
}

#Preview {
    OnboardingView {}
}
