import CoreLocation
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
}
