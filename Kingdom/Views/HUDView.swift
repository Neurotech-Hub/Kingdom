import SwiftUI

struct HUDView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            footer
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                appState.isARPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Home")

            Image("KingdomMark")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
            Text("Kingdom")
                .font(Brand.font(17, weight: .bold))
            Spacer()
            Text(statusText)
                .font(Brand.font(13, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .foregroundStyle(Brand.mist)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !appState.instances.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.instances) { summary in
                            chip(for: summary)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }

            HStack(spacing: 12) {
                Button {
                    appState.showLabels.toggle()
                } label: {
                    Image(systemName: appState.showLabels ? "text.bubble.fill" : "text.bubble")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(appState.showLabels ? "Hide labels" : "Show labels")

                Spacer()

                Button {
                    appState.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .font(Brand.font(15, weight: .semibold))
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                }
            }
            .foregroundStyle(Brand.mist)
            .buttonStyle(.plain)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .environment(\.colorScheme, .dark)
        }
    }

    private func chip(for summary: AnimalInstanceSummary) -> some View {
        let animal = appState.animal(for: summary)
        let isSelected = summary.id == appState.selectedInstanceID
        return Button {
            appState.selectedInstanceID = summary.id
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(summary.trackingState == .stale ? Brand.sand.opacity(0.5) : Brand.forest)
                    .frame(width: 7, height: 7)
                Text(animal?.displayName ?? summary.speciesID)
                    .font(Brand.font(13, weight: .semibold))
                if let length = animal?.dimensions.headBodyLengthMeters {
                    Text(DisplayFormat.lengthString(meters: length))
                        .font(Brand.font(12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(Brand.mist)
            .background(isSelected ? AnyShapeStyle(Brand.forest.opacity(0.85)) : AnyShapeStyle(.ultraThinMaterial.opacity(0.9)), in: Capsule())
        }
        .buttonStyle(.plain)
        .environment(\.colorScheme, .dark)
    }

    private var statusText: String {
        if let message = appState.trackingMessage { return message }
        switch appState.instances.count {
        case 0: return "Point at a Kingdom tag"
        case 1: return "1 animal · true scale"
        default: return "\(appState.instances.count) animals · true scale"
        }
    }
}

nonisolated enum DisplayFormat {
    static func lengthString(meters: Double) -> String {
        meters < 1 ? String(format: "%.1f cm", meters * 100) : String(format: "%.2f m", meters)
    }

    static func massString(grams: Double) -> String {
        grams < 1000 ? String(format: "%.0f g", grams) : String(format: "%.2f kg", grams / 1000)
    }
}
