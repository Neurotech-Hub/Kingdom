import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum CameraAccess {
        case unknown
        case authorized
        case denied
    }

    let catalog: AnimalCatalog?
    let catalogError: String?
    let sessionManager: ARSessionManager?

    var instances: [AnimalInstanceSummary] = []
    var trackingMessage: String?
    var cameraAccess: CameraAccess = .unknown

    var selectedInstanceID: UUID? {
        didSet { sessionManager?.anchorManager.setSelected(selectedInstanceID) }
    }

    var showLabels = true {
        didSet { sessionManager?.anchorManager.labelsVisible = showLabels }
    }

    /// Whether the AR viewer is on screen. Leaving it stops the session and clears placed animals.
    var isARPresented = false {
        didSet {
            guard oldValue, !isARPresented else { return }
            selectedInstanceID = nil
            sessionManager?.stop()
        }
    }

    var assetManager: AnimalAssetManager? { sessionManager?.assetManager }

    init() {
        do {
            let catalog = try CatalogLoader.loadBundled()
            self.catalog = catalog
            catalogError = nil
            sessionManager = ARSessionManager(catalog: catalog)
        } catch {
            catalog = nil
            catalogError = error.localizedDescription
            sessionManager = nil
        }

        sessionManager?.onInstancesChanged = { [weak self] summaries in
            guard let self else { return }
            instances = summaries
            if let selected = selectedInstanceID, !summaries.contains(where: { $0.id == selected }) {
                selectedInstanceID = nil
            }
        }
        sessionManager?.onTrackingMessage = { [weak self] message in
            self?.trackingMessage = message
        }
    }

    var selectedInstance: AnimalInstanceSummary? {
        instances.first { $0.id == selectedInstanceID }
    }

    func animal(for summary: AnimalInstanceSummary) -> AnimalDefinition? {
        catalog?.animal(id: summary.speciesID)
    }

    func requestCameraAccess() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraAccess = .authorized
        case .notDetermined:
            cameraAccess = await AVCaptureDevice.requestAccess(for: .video) ? .authorized : .denied
        default:
            cameraAccess = .denied
        }
    }

    func reset() {
        selectedInstanceID = nil
        sessionManager?.reset()
    }
}
