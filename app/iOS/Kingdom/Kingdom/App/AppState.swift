import AVFoundation
import Foundation
import Observation
import Photos
import UIKit

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

    // MARK: Photo capture

    private(set) var isCapturingPhoto = false
    /// Incremented on each successful capture to drive the shutter flash.
    private(set) var photoFlashCount = 0
    /// Short result shown in the HUD after a capture.
    private(set) var photoMessage: String?

    func capturePhoto() async {
        guard !isCapturingPhoto, let sessionManager else { return }
        isCapturingPhoto = true
        defer { isCapturingPhoto = false }

        guard let image = await sessionManager.captureSnapshot() else {
            showPhotoMessage("Couldn't capture photo")
            return
        }
        photoFlashCount += 1

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            showPhotoMessage("Allow Photos access in Settings")
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            showPhotoMessage("Saved to Photos")
        } catch {
            showPhotoMessage("Couldn't save photo")
        }
    }

    private func showPhotoMessage(_ message: String) {
        photoMessage = message
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, photoMessage == message else { return }
            photoMessage = nil
        }
    }
}
