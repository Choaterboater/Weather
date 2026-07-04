import CoreLocation
import CryptoKit
import Foundation

/// Loads bundled curated fishing spots and answers proximity queries against
/// the user's location. Spots are hand-authored in `Sources/Support/Spots/curated.json`
/// and shipped with the app — no network required.
@MainActor
@Observable
final class CuratedSpotCatalog {
    private(set) var spots: [FishingSpot] = []

    init() {
        load()
    }

    /// Curated spots within `radiusMiles` of `location`, nearest first.
    func nearby(_ location: CLLocation, within radiusMiles: Double = 75) -> [FishingSpot] {
        let radiusMeters = radiusMiles * 1609.34
        return spots
            .map { (spot: $0, distance: location.distance(from: $0.location)) }
            .filter { $0.distance <= radiusMeters }
            .sorted { $0.distance < $1.distance }
            .map(\.spot)
    }

    private struct Wrapper: Decodable {
        let spots: [Entry]
    }

    private struct Entry: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let waterType: WaterType
        let kind: SpotKind
        let stateCode: String
        let targetSpecies: [Species]
        let notes: String?
    }

    private func load() {
        let bundle = Bundle.main
        let candidates = [
            bundle.url(forResource: "curated", withExtension: "json", subdirectory: "Spots"),
            bundle.url(forResource: "curated", withExtension: "json")
        ].compactMap { $0 }
        guard let url = candidates.first,
              let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(Wrapper.self, from: data) else {
            return
        }
        spots = wrapper.spots.map { entry in
            FishingSpot(
                id: Self.stableID(name: entry.name, latitude: entry.latitude, longitude: entry.longitude),
                name: entry.name,
                latitude: entry.latitude,
                longitude: entry.longitude,
                waterType: entry.waterType,
                kind: entry.kind,
                stateCode: entry.stateCode,
                targetSpecies: entry.targetSpecies,
                notes: entry.notes
            )
        }
    }

    /// Deterministic ID so "Set as active" doesn't mint a new saved copy every launch.
    nonisolated static func stableID(name: String, latitude: Double, longitude: Double) -> UUID {
        let key = "\(name)|\(String(format: "%.5f", latitude))|\(String(format: "%.5f", longitude))"
        let digest = SHA256.hash(data: Data(key.utf8))
        let bytes = Array(digest.prefix(16))
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
