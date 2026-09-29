import Foundation
import RealityKit
import simd

/// One animal placed in the scene for one detected card. Each card gets its own instance.
final class AnimalInstance: Identifiable {
    enum TrackingState: String, Sendable {
        /// Seen once; pose is still being refined.
        case detected
        /// Seen recently.
        case tracking
        /// Not seen for a while; held in place by world tracking.
        case stale
    }

    let id = UUID()
    let speciesID: String
    let cardID: String
    let markerID: Int
    let anchor: AnchorEntity
    var entity: Entity?
    var trackingState: TrackingState = .detected
    var lastSeen: TimeInterval
    var observationCount = 0
    var smoothedTransform: simd_float4x4

    init(speciesID: String, cardID: String, markerID: Int, anchor: AnchorEntity, initialTransform: simd_float4x4, timestamp: TimeInterval) {
        self.speciesID = speciesID
        self.cardID = cardID
        self.markerID = markerID
        self.anchor = anchor
        self.smoothedTransform = initialTransform
        self.lastSeen = timestamp
    }
}

/// Value snapshot of an instance for SwiftUI.
nonisolated struct AnimalInstanceSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let speciesID: String
    let markerID: Int
    let trackingState: AnimalInstance.TrackingState
}
