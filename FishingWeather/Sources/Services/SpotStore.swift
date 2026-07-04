import Foundation
import Observation

/// Stores saved fishing spots and which one is active, persisted in UserDefaults.
/// When no spot is selected, the app uses the device's current location.
@MainActor
@Observable
final class SpotStore {
    private(set) var spots: [FishingSpot] = []
    var selectedSpotID: UUID? {
        didSet { UserDefaults.standard.set(selectedSpotID?.uuidString, forKey: Self.selectionKey) }
    }

    private static let spotsKey = "savedSpots"
    private static let selectionKey = "selectedSpotID"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.spotsKey),
           let decoded = try? JSONDecoder().decode([FishingSpot].self, from: data) {
            spots = Self.deduplicated(decoded)
        }
        if let idString = UserDefaults.standard.string(forKey: Self.selectionKey) {
            selectedSpotID = UUID(uuidString: idString)
        }
        // Drop a selection that no longer points at a saved spot.
        if let id = selectedSpotID, !spots.contains(where: { $0.id == id }) {
            selectedSpotID = nil
        }
    }

    var selectedSpot: FishingSpot? {
        guard let id = selectedSpotID else { return nil }
        return spots.first { $0.id == id }
    }

    func add(_ spot: FishingSpot) {
        if spots.contains(where: { $0.id == spot.id || $0.isSamePlace(as: spot) }) { return }
        spots.append(spot)
        persistSpots()
    }

    func remove(_ spot: FishingSpot) {
        let removedIDs = Set(spots.filter { $0.id == spot.id || $0.isSamePlace(as: spot) }.map(\.id))
        spots.removeAll { removedIDs.contains($0.id) }
        if let id = selectedSpotID, removedIDs.contains(id) {
            selectedSpotID = nil
        }
        persistSpots()
    }

    func select(_ spot: FishingSpot?) {
        guard let spot else {
            selectedSpotID = nil
            return
        }
        if let existing = spots.first(where: { $0.id == spot.id || $0.isSamePlace(as: spot) }) {
            selectedSpotID = existing.id
        } else {
            selectedSpotID = spot.id
        }
    }

    /// Activate a spot, adding it only when it isn't already saved (by id or place).
    /// Migrates legacy random-UUID saves to the catalog's stable id when they match.
    func activate(_ spot: FishingSpot) {
        if let idx = spots.firstIndex(where: { $0.id == spot.id || $0.isSamePlace(as: spot) }) {
            if spots[idx].id != spot.id {
                spots[idx] = spot
                persistSpots()
            }
            selectedSpotID = spot.id
            return
        }
        spots.append(spot)
        selectedSpotID = spot.id
        persistSpots()
    }

    private func persistSpots() {
        if let data = try? JSONEncoder().encode(spots) {
            UserDefaults.standard.set(data, forKey: Self.spotsKey)
        }
    }

    /// Keep the first entry per place so legacy duplicate curated saves collapse.
    private static func deduplicated(_ spots: [FishingSpot]) -> [FishingSpot] {
        var result: [FishingSpot] = []
        for spot in spots {
            if !result.contains(where: { $0.isSamePlace(as: spot) }) {
                result.append(spot)
            }
        }
        return result
    }
}
