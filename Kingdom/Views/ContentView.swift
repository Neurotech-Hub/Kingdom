//
//  ContentView.swift
//  Kingdom
//
//  Created by Matt Gaidica on 9/29/26.
//

import SwiftUI

struct ContentView: View {
    @State private var appState = AppState()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let error = appState.catalogError {
                message(title: "Catalog error", detail: error)
            } else if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else if let catalog = appState.catalog, appState.assetManager != nil {
                HomeView(appState: appState, catalog: catalog)
            }
        }
        .fullScreenCover(isPresented: $appState.isARPresented) {
            arViewer
        }
        .onChange(of: scenePhase) { _, phase in
            guard appState.isARPresented, appState.cameraAccess == .authorized else { return }
            switch phase {
            case .active: appState.sessionManager?.run()
            case .background: appState.sessionManager?.pause()
            default: break
            }
        }
    }

    @ViewBuilder
    private var arViewer: some View {
        if !ARSessionManager.isSupported {
            closable(message(title: "AR not available", detail: "Kingdom needs a device that supports ARKit world tracking."))
        } else {
            switch appState.cameraAccess {
            case .authorized:
                experience
            case .denied:
                closable(cameraDenied)
            case .unknown:
                Brand.charcoal.ignoresSafeArea()
                    .task { await appState.requestCameraAccess() }
            }
        }
    }

    private func closable(_ content: some View) -> some View {
        content.overlay(alignment: .topLeading) {
            Button {
                appState.isARPresented = false
            } label: {
                Label("Home", systemImage: "chevron.left")
                    .font(Brand.font(16, weight: .semibold))
                    .foregroundStyle(Brand.forest)
                    .padding(20)
            }
        }
    }

    @ViewBuilder
    private var experience: some View {
        if let sessionManager = appState.sessionManager {
            ZStack {
                ARViewContainer(sessionManager: sessionManager) { id in
                    appState.selectedInstanceID = id
                }
                .ignoresSafeArea()

                HUDView(appState: appState)
            }
            .sheet(item: selectedBinding) { summary in
                if let animal = appState.animal(for: summary) {
                    AnimalInfoView(animal: animal, markerID: summary.markerID, trackingState: summary.trackingState)
                        .presentationDetents([.height(360), .large])
                        .presentationBackground(Brand.mist)
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    private var selectedBinding: Binding<AnimalInstanceSummary?> {
        Binding(
            get: { appState.selectedInstance },
            set: { appState.selectedInstanceID = $0?.id }
        )
    }

    private var cameraDenied: some View {
        VStack(spacing: 16) {
            message(title: "Camera access needed", detail: "Kingdom uses the camera to find tags and place animals at true scale.")
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Open Settings", destination: url)
                    .font(Brand.font(17, weight: .semibold))
                    .foregroundStyle(Brand.forest)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.mist.ignoresSafeArea())
    }

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image("KingdomMark")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            Text(title)
                .font(Brand.font(20, weight: .bold))
            Text(detail)
                .font(Brand.font(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .foregroundStyle(Brand.charcoal)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Brand.mist.ignoresSafeArea())
    }
}

#Preview {
    ContentView()
}
