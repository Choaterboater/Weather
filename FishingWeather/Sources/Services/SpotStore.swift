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
            spots = decoded
        }
        if let idString = UserDefaults.standard.string(forKey: Self.selectionKey) {
            selectedSpotID = UUID(uuidString: idString)
        }
    }

    var selectedSpot: FishingSpot? {
        guard let id = selectedSpotID else { return nil }
        return spots.first { $0.id == id }
    }

    func add(_ spot: FishingSpot) {
        spots.append(spot)
        persistSpots()
    }

    func remove(_ spot: FishingSpot) {
        spots.removeAll { $0.id == spot.id }
        if selectedSpotID == spot.id { selectedSpotID = nil }
        persistSpots()
    }

    func select(_ spot: FishingSpot?) {
        selectedSpotID = spot?.id
    }

    private func persistSpots() {
        if let data = try? JSONEncoder().encode(spots) {
            UserDefaults.standard.set(data, forKey: Self.spotsKey)
        }
    }
}
